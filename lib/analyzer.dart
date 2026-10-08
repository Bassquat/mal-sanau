import 'dart:typed_data';

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
  VideoAnalyzer._(this._interpreter, this._scoresIdx, this._boxesIdx);

  final Interpreter _interpreter;
  final int _scoresIdx, _boxesIdx;
  final Float32List _anchors = buildAnchors();

  static Future<VideoAnalyzer> load() async {
    final it = await Interpreter.fromAsset(
        'assets/models/efficientdet_lite0.tflite');
    final firstIsScores = it.getOutputTensor(0).shape.last == numClasses;
    return VideoAnalyzer._(it, firstIsScores ? 0 : 1, firstIsScores ? 1 : 0);
  }

  void close() => _interpreter.close();

  Future<AnalysisResult> analyze(
    String videoPath, {
    required int durationMs,
    required GateLine line,
    int fps = 4,
    void Function(double progress)? onProgress,
  }) async {
    final tracker = CentroidTracker();
    GateCounter? gate;
    var frames = 0;
    final step = 1000 ~/ fps;
    for (var t = 0; t < durationMs; t += step) {
      onProgress?.call(t / durationMs);
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 640,
        timeMs: t,
        quality: 85,
      );
      if (bytes == null) continue;
      final image = img.decodeJpg(bytes);
      if (image == null) continue;
      frames++;

      final w = image.width.toDouble(), h = image.height.toDouble();
      gate ??= _makeGate(w, h, line);
      final dets = nms(_detect(image));
      gate.update(tracker.update(dets));
    }
    onProgress?.call(1);
    return AnalysisResult(gate?.nIn ?? 0, gate?.nOut ?? 0, frames);
  }

  GateCounter _makeGate(double w, double h, GateLine line) {
    final (a, b) = line.ordered;
    return GateCounter(
      ax: a.dx * w,
      ay: a.dy * h,
      bx: b.dx * w,
      by: b.dy * h,
      margin: h * 0.02,
      limitToSegment: true,
    );
  }

  List<Detection> _detect(img.Image image) {
    final scale = inputSize / (image.width > image.height ? image.width : image.height);
    final nw = (image.width * scale).round();
    final nh = (image.height * scale).round();
    final resized = img.copyResize(image, width: nw, height: nh);
    final canvas = img.Image(width: inputSize, height: inputSize);
    img.compositeImage(canvas, resized);

    final input = Float32List(inputSize * inputSize * 3);
    var k = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final p = canvas.getPixel(x, y);
        input[k++] = (p.r - 127.5) / 127.5;
        input[k++] = (p.g - 127.5) / 127.5;
        input[k++] = (p.b - 127.5) / 127.5;
      }
    }

    final n = _anchors.length ~/ 4;
    final scoresOut = List.generate(
        1, (_) => List.generate(n, (_) => List<double>.filled(numClasses, 0)));
    final boxesOut =
        List.generate(1, (_) => List.generate(n, (_) => List<double>.filled(4, 0)));
    _interpreter.runForMultipleInputs(
      [input.reshape([1, inputSize, inputSize, 3])],
      {_scoresIdx: scoresOut, _boxesIdx: boxesOut},
    );

    final scores = Float32List(n * numClasses);
    final boxes = Float32List(n * 4);
    for (var i = 0; i < n; i++) {
      for (var c = 0; c < numClasses; c++) {
        scores[i * numClasses + c] = scoresOut[0][i][c];
      }
      for (var c = 0; c < 4; c++) {
        boxes[i * 4 + c] = boxesOut[0][i][c];
      }
    }
    return decode(boxes, scores, _anchors, scale: scale);
  }
}
