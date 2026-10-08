import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'analyzer.dart';
import 'gate_line.dart';

/// Counts from a live camera stream. Frames are converted, detected and
/// counted in a background isolate; [process] drops frames while the worker is
/// still busy, so a slow phone just counts fewer frames per second.
class LiveCounter {
  LiveCounter._(this._isolate, this._port, this._events, this._worker);

  final Isolate _isolate;
  final ReceivePort _port;
  final StreamIterator<dynamic> _events;
  final SendPort _worker;
  bool _busy = false;

  static Future<LiveCounter> start(GateLine line) async {
    final analyzer = await VideoAnalyzer.load();
    final port = ReceivePort();
    final events = StreamIterator<dynamic>(port);
    final isolate = await Isolate.spawn(
        analysisWorker, WorkerInit(port.sendPort, analyzer.modelBytes, line));
    await events.moveNext();
    return LiveCounter._(isolate, port, events, events.current as SendPort);
  }

  /// Returns [nIn, nOut], or null when the frame was skipped.
  Future<List<int>?> process(CameraImage image, int rotation) async {
    if (_busy || image.planes.length < 3) return null;
    _busy = true;
    try {
      final p = image.planes;
      _worker.send([
        image.width,
        image.height,
        p[0].bytesPerRow,
        p[1].bytesPerRow,
        p[1].bytesPerPixel ?? 1,
        rotation,
        TransferableTypedData.fromList([Uint8List.fromList(p[0].bytes)]),
        TransferableTypedData.fromList([Uint8List.fromList(p[1].bytes)]),
        TransferableTypedData.fromList([Uint8List.fromList(p[2].bytes)]),
      ]);
      await _events.moveNext();
      final r = _events.current;
      if (r is String) throw Exception(r);
      return (r as List).cast<int>();
    } finally {
      _busy = false;
    }
  }

  Future<void> close() async {
    _isolate.kill(priority: Isolate.immediate);
    await _events.cancel();
    _port.close();
  }
}
