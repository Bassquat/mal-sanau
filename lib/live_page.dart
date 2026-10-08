import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gate_line.dart';
import 'herd.dart';
import 'history_store.dart';
import 'live.dart';

/// Live counting with the phone's own camera: mount the phone at the gate,
/// place the line over the preview, press start. Detection runs in a
/// background isolate at a few frames per second.
class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.store});
  final HistoryStore store;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  static const _frameGap = Duration(milliseconds: 300);

  CameraController? _cam;
  LiveCounter? _counter;
  GateLine _line = GateLine.initial;
  bool _dragging = false;
  bool _running = false;
  int _in = 0;
  int _out = 0;
  int _frames = 0;
  int? _registered;
  String? _error;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initCamera();
    HerdStore().load().then((h) {
      if (mounted) setState(() => _registered = h.totalAlive);
    });
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.low,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _cam = c);
    } catch (e) {
      if (mounted) setState(() => _error = 'Камера ашылмады: $e');
    }
  }

  Future<void> _start() async {
    final cam = _cam;
    if (cam == null) return;
    try {
      final counter = await LiveCounter.start(_line);
      _counter = counter;
      final rotation = cam.description.sensorOrientation;
      setState(() {
        _running = true;
        _in = 0;
        _out = 0;
        _frames = 0;
        _error = null;
      });
      await cam.startImageStream((image) {
        final now = DateTime.now();
        if (now.difference(_last) < _frameGap) return;
        _last = now;
        counter.process(image, rotation).then((r) {
          if (r != null && mounted && _running) {
            setState(() {
              _in = r[0];
              _out = r[1];
              _frames++;
            });
          }
        }).catchError((Object e) {
          if (mounted) setState(() => _error = 'Қате: $e');
        });
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Қате: $e');
      await _stop();
    }
  }

  Future<void> _stop() async {
    final cam = _cam;
    if (cam != null && cam.value.isStreamingImages) {
      await cam.stopImageStream();
    }
    await _counter?.close();
    _counter = null;
    if (mounted) setState(() => _running = false);
  }

  Future<void> _stopAndSave() async {
    await _stop();
    if (_in + _out > 0) {
      await widget.store.add(CountEntry(
        time: DateTime.now(),
        source: 'тікелей',
        nIn: _in,
        nOut: _out,
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    final cam = _cam;
    _running = false;
    () async {
      try {
        if (cam != null && cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
      } catch (_) {}
      await _counter?.close();
      await cam?.dispose();
    }();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    return Scaffold(
      appBar: AppBar(title: const Text('Тікелей санау')),
      body: SingleChildScrollView(
        physics: _dragging ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (cam == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: Colors.red))
                    : const CircularProgressIndicator(),
              )
            else
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: AspectRatio(
                    aspectRatio: 1 / cam.value.aspectRatio,
                    child: Stack(
                      children: [
                        Positioned.fill(child: CameraPreview(cam)),
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: _running,
                            child: GateLineEditor(
                              line: _line,
                              onChanged: (l) => setState(() => _line = l),
                              onDragging: (d) => setState(() => _dragging = d),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _running
                  ? 'Санап жатыр. Телефонды қуатқа қосып, қозғалтпаңыз.'
                  : 'Телефонды қақпаға бекітіп, қызыл сызықты қақпаға қойыңыз '
                      '(1 және 2 нүктесін сүйреңіз). Көрсеткі жаққа өту = кірді.',
              style: const TextStyle(color: Colors.grey),
            ),
            if (!_running)
              SwitchListTile(
                dense: true,
                title: const Text('Бағытты ауыстыру (кірді ↔ шықты)'),
                value: _line.invert,
                onChanged: (x) =>
                    setState(() => _line = _line.copyWith(invert: x)),
              ),
            const SizedBox(height: 8),
            Text('Баланс: ${_in - _out}',
                style: Theme.of(context).textTheme.headlineMedium),
            Row(
              children: [
                Expanded(
                    child: Card(
                        child: ListTile(
                            title: const Text('Кірді'),
                            subtitle: Text('$_in',
                                style:
                                    Theme.of(context).textTheme.headlineSmall)))),
                Expanded(
                    child: Card(
                        child: ListTile(
                            title: const Text('Шықты'),
                            subtitle: Text('$_out',
                                style:
                                    Theme.of(context).textTheme.headlineSmall)))),
              ],
            ),
            if (_running)
              Text('Өңделген кадр: $_frames',
                  style: const TextStyle(color: Colors.grey)),
            if ((_registered ?? 0) > 0)
              Text('Тіркелген тірі мал: $_registered',
                  style: const TextStyle(color: Colors.grey)),
            if (_error != null && cam != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _running
                  ? FilledButton(
                      onPressed: _stopAndSave,
                      child: const Text('Тоқтату және сақтау'))
                  : FilledButton(
                      onPressed: cam == null ? null : _start,
                      child: const Text('Санауды бастау')),
            ),
          ],
        ),
      ),
    );
  }
}
