import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'detect_math.dart';
import 'gate_counter.dart';
import 'gate_line.dart';

/// One tracked animal in a frame; x and y are fractions of the frame.
class TrackMark {
  const TrackMark(this.id, this.x, this.y);
  final int id;
  final double x, y;
}

/// An animal that was just counted at (x, y); [dir] is +1 for in, -1 for out
/// and [seq] its running number within that direction.
class CountEvent {
  const CountEvent(this.timeMs, this.id, this.dir, this.seq, this.x, this.y);
  final int timeMs, id, dir, seq;
  final double x, y;
}

class FrameInfo {
  const FrameInfo(this.timeMs, this.nIn, this.nOut, this.tracks, this.crossings);
  final int timeMs, nIn, nOut;
  final List<TrackMark> tracks;

  /// (id, dir, x, y) of animals counted in this frame.
  final List<(int, int, double, double)> crossings;

  factory FrameInfo.fromReply(int timeMs, List r) {
    final t = (r[2] as List).cast<double>();
    final e = (r[3] as List).cast<double>();
    return FrameInfo(
      timeMs,
      r[0] as int,
      r[1] as int,
      [for (var i = 0; i + 2 < t.length; i += 3) TrackMark(t[i].toInt(), t[i + 1], t[i + 2])],
      [
        for (var i = 0; i + 3 < e.length; i += 4)
          (e[i].toInt(), e[i + 1].toInt(), e[i + 2], e[i + 3])
      ],
    );
  }
}

class AnalysisResult {
  AnalysisResult(this.nIn, this.nOut, this.frames);
  final int nIn, nOut, frames;
}

/// Offline analysis of a video: sample frames, detect livestock with
/// EfficientDet-Lite0, track them and count crossings of a gate line drawn at
/// any angle (see [GateLine]); crossing towards the arrow side = "in".
class VideoAnalyzer {
  VideoAnalyzer._(this._model);

  final Uint8List _model;

  static Future<VideoAnalyzer> load() async {
    final data = await rootBundle.load('assets/models/efficientdet_lite0.tflite');
    return VideoAnalyzer._(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  Uint8List get modelBytes => _model;

  void close() {}

  /// Frames are pulled here (native work, async) and decoded, detected and
  /// counted in a background isolate, so the UI thread stays free.
  Future<AnalysisResult> analyze(
    String videoPath, {
    required int durationMs,
    required GateLine line,
    int fps = 4,
    void Function(double progress)? onProgress,
    void Function(FrameInfo frame)? onFrame,
  }) async {
    final rp = ReceivePort();
    final events = StreamIterator<dynamic>(rp);
    final isolate = await Isolate.spawn(analysisWorker, WorkerInit(rp.sendPort, _model, line));
    try {
      await events.moveNext();
      final worker = events.current as SendPort;
      var frames = 0;
      final step = 1000 ~/ fps;
      Future<Uint8List?> fetch(int t) => VideoThumbnail.thumbnailData(
            video: videoPath,
            imageFormat: ImageFormat.JPEG,
            maxWidth: inputSize,
            maxHeight: inputSize,
            timeMs: t,
            quality: 70,
          );
      // The next frame is extracted while the worker detects the current one.
      Future<Uint8List?>? next = durationMs > 0 ? fetch(0) : null;
      for (var t = 0; t < durationMs; t += step) {
        onProgress?.call(t / durationMs);
        final bytes = await next;
        next = t + step < durationMs ? fetch(t + step) : null;
        if (bytes == null) continue;
        worker.send(TransferableTypedData.fromList([bytes]));
        await events.moveNext();
        final r = events.current;
        if (r is String) throw Exception(r);
        onFrame?.call(FrameInfo.fromReply(t, r as List));
        frames++;
      }
      worker.send(null);
      await events.moveNext();
      final r = events.current;
      if (r is String) throw Exception(r);
      onProgress?.call(1);
      final counts = (r as List).cast<int>();
      return AnalysisResult(counts[0], counts[1], frames);
    } finally {
      isolate.kill(priority: Isolate.immediate);
      await events.cancel();
      rp.close();
    }
  }
}

class WorkerInit {
  WorkerInit(this.reply, this.model, GateLine line)
      : p1x = line.ordered.$1.dx,
        p1y = line.ordered.$1.dy,
        p2x = line.ordered.$2.dx,
        p2y = line.ordered.$2.dy;
  final SendPort reply;
  final Uint8List model;
  final double p1x, p1y, p2x, p2y;
}

void analysisWorker(WorkerInit init) {
  final port = ReceivePort();
  init.reply.send(port.sendPort);
  late final _Detector detector;
  var ready = false;
  String? failure;
  try {
    detector = _Detector(init.model);
    ready = true;
  } catch (e) {
    failure = 'Модель ашылмады: $e';
  }
  CentroidTracker? tracker;
  GateCounter? gate;
  port.listen((msg) {
    if (!ready) {
      init.reply.send(failure);
      return;
    }
    if (msg == null) {
      init.reply.send(<int>[gate?.nIn ?? 0, gate?.nOut ?? 0]);
      detector.close();
      port.close();
      return;
    }
    try {
      final image = msg is TransferableTypedData
          ? img.decodeJpg(msg.materialize().asUint8List())
          : yuvMessageToImage(msg as List);
      if (image != null) {
        final w = image.width.toDouble(), h = image.height.toDouble();
        gate ??= GateCounter(
          ax: init.p1x * w,
          ay: init.p1y * h,
          bx: init.p2x * w,
          by: init.p2y * h,
          margin: h * 0.02,
          limitToSegment: true,
        );
        tracker ??= CentroidTracker(maxDist: 0.25 * math.sqrt(w * w + h * h));
        final tracks = tracker!.update(nms(detector.detect(image)));
        final crossed = gate!.update(tracks);
        init.reply.send(<Object>[
          gate!.nIn,
          gate!.nOut,
          <double>[
            for (final e in tracks.entries) ...[e.key.toDouble(), e.value.$1 / w, e.value.$2 / h]
          ],
          <double>[
            for (final c in crossed) ...[
              c.$1.toDouble(),
              c.$2.toDouble(),
              tracks[c.$1]!.$1 / w,
              tracks[c.$1]!.$2 / h,
            ]
          ],
        ]);
        return;
      }
      init.reply.send(<Object>[gate?.nIn ?? 0, gate?.nOut ?? 0, <double>[], <double>[]]);
    } catch (e) {
      init.reply.send('Кадрды өңдеу қатесі: $e');
    }
  });
}

class _Detector {
  _Detector(Uint8List model) : _interpreter = Interpreter.fromBuffer(model) {
    final firstIsScores = _interpreter.getOutputTensor(0).shape.last == numClasses;
    _scoresIdx = firstIsScores ? 0 : 1;
    _boxesIdx = firstIsScores ? 1 : 0;
    final n = _anchors.length ~/ 4;
    _scoresOut = List.generate(
        1, (_) => List.generate(n, (_) => List<double>.filled(numClasses, 0)));
    _boxesOut = List.generate(
        1, (_) => List.generate(n, (_) => List<double>.filled(4, 0)));
    _scores = Float32List(n * numClasses);
    _boxes = Float32List(n * 4);
  }

  final Interpreter _interpreter;
  late final int _scoresIdx, _boxesIdx;
  final Float32List _anchors = buildAnchors();
  late final List<List<List<double>>> _scoresOut, _boxesOut;
  late final Float32List _scores, _boxes;
  final Float32List _input = Float32List(inputSize * inputSize * 3);

  void close() => _interpreter.close();

  List<Detection> detect(img.Image image) {
    final scale =
        inputSize / (image.width > image.height ? image.width : image.height);
    final nw = (image.width * scale).round();
    final nh = (image.height * scale).round();
    final resized = (nw == image.width && nh == image.height)
        ? image
        : img.copyResize(image, width: nw, height: nh);

    _input.fillRange(0, _input.length, -1.0); // black padding
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        final p = resized.getPixel(x, y);
        final k = (y * inputSize + x) * 3;
        _input[k] = (p.r - 127.5) / 127.5;
        _input[k + 1] = (p.g - 127.5) / 127.5;
        _input[k + 2] = (p.b - 127.5) / 127.5;
      }
    }

    _interpreter.runForMultipleInputs(
      [_input.reshape([1, inputSize, inputSize, 3])],
      {_scoresIdx: _scoresOut, _boxesIdx: _boxesOut},
    );

    final n = _anchors.length ~/ 4;
    for (var i = 0; i < n; i++) {
      final row = _scoresOut[0][i];
      for (var c = 0; c < numClasses; c++) {
        _scores[i * numClasses + c] = row[c];
      }
      final b = _boxesOut[0][i];
      for (var c = 0; c < 4; c++) {
        _boxes[i * 4 + c] = b[c];
      }
    }
    return decode(_boxes, _scores, _anchors, scale: scale);
  }
}

/// Builds an RGB image from a camera YUV420 frame sent as
/// [w, h, yStride, uvStride, uvPixelStride, rotationDegrees, y, u, v], where
/// y, u and v are [TransferableTypedData]. The result is rotated clockwise by
/// the rotation so it matches the upright preview.
img.Image yuvMessageToImage(List m) {
  final w = m[0] as int, h = m[1] as int;
  final yStride = m[2] as int, uvStride = m[3] as int, uvPix = m[4] as int;
  final rot = m[5] as int;
  final y = (m[6] as TransferableTypedData).materialize().asUint8List();
  final u = (m[7] as TransferableTypedData).materialize().asUint8List();
  final v = (m[8] as TransferableTypedData).materialize().asUint8List();
  final out = img.Image(width: w, height: h);
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      final yy = y[j * yStride + i];
      final k = (j >> 1) * uvStride + (i >> 1) * uvPix;
      final uu = u[k] - 128, vv = v[k] - 128;
      out.setPixelRgb(
        i,
        j,
        (yy + 1.402 * vv).round().clamp(0, 255),
        (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255),
        (yy + 1.772 * uu).round().clamp(0, 255),
      );
    }
  }
  return rot == 0 ? out : img.copyRotate(out, angle: rot);
}
