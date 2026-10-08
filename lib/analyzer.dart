import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'detect_math.dart';
import 'gate_counter.dart';
import 'gate_line.dart';

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

  void close() {}

  /// Frames are pulled here (native work, async) and decoded, detected and
  /// counted in a background isolate, so the UI thread stays free.
  Future<AnalysisResult> analyze(
    String videoPath, {
    required int durationMs,
    required GateLine line,
    int fps = 4,
    void Function(double progress)? onProgress,
  }) async {
    final rp = ReceivePort();
    final events = StreamIterator<dynamic>(rp);
    final isolate = await Isolate.spawn(_worker, _Init(rp.sendPort, _model, line));
    try {
      await events.moveNext();
      final worker = events.current as SendPort;
      var frames = 0;
      final step = 1000 ~/ fps;
      for (var t = 0; t < durationMs; t += step) {
        onProgress?.call(t / durationMs);
        final bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: inputSize,
          maxHeight: inputSize,
          timeMs: t,
          quality: 80,
        );
        if (bytes == null) continue;
        worker.send(TransferableTypedData.fromList([bytes]));
        await events.moveNext();
        final r = events.current;
        if (r is String) throw Exception(r);
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

class _Init {
  _Init(this.reply, this.model, GateLine line)
      : p1x = line.ordered.$1.dx,
        p1y = line.ordered.$1.dy,
        p2x = line.ordered.$2.dx,
        p2y = line.ordered.$2.dy;
  final SendPort reply;
  final Uint8List model;
  final double p1x, p1y, p2x, p2y;
}

void _worker(_Init init) {
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
  final tracker = CentroidTracker();
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
      final bytes = (msg as TransferableTypedData).materialize().asUint8List();
      final image = img.decodeJpg(bytes);
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
        gate!.update(tracker.update(nms(detector.detect(image))));
      }
      init.reply.send(0);
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
