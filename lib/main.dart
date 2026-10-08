import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'analyzer.dart';
import 'gate_line.dart';
import 'history_store.dart';

void main() => runApp(const MalSanauApp());

class MalSanauApp extends StatelessWidget {
  const MalSanauApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Мал санау',
        theme: ThemeData(
          colorSchemeSeed: Colors.green,
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _store = HistoryStore();
  List<CountEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final e = await _store.load();
    if (mounted) setState(() => _entries = e);
  }

  Future<void> _newCount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CountPage(store: _store)),
    );
    _reload();
  }

  String _fmt(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Мал санау')),
        body: _entries.isEmpty
            ? const Center(child: Text('Тарих бос. Жаңа санауды бастаңыз.'))
            : ListView(
                children: [
                  for (final e in _entries)
                    ListTile(
                      title: Text('Баланс: ${e.balance}'),
                      subtitle: Text(
                          '${_fmt(e.time)} · кірді ${e.nIn}, шықты ${e.nOut}\n${e.source}'),
                      isThreeLine: true,
                    ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newCount,
          icon: const Icon(Icons.add),
          label: const Text('Жаңа санау'),
        ),
      );
}

/// Milestone 1: pick a video from the gallery and count by hand (+1 in,
/// +1 out). The automatic detector plugs in here in the next milestone, and
/// these manual counts become the ground truth for measuring its accuracy.
class CountPage extends StatefulWidget {
  const CountPage({super.key, required this.store});
  final HistoryStore store;

  @override
  State<CountPage> createState() => _CountPageState();
}

class _CountPageState extends State<CountPage> {
  VideoPlayerController? _video;
  String _name = '';
  int _in = 0;
  int _out = 0;
  String _path = '';
  GateLine _line = GateLine.initial;
  double? _progress;
  String? _error;

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _video?.dispose();
    final c = VideoPlayerController.file(File(picked.path));
    await c.initialize();
    setState(() {
      _video = c;
      _name = picked.name;
      _path = picked.path;
      _error = null;
      _in = 0;
      _out = 0;
    });
  }

  Future<void> _auto() async {
    final v = _video;
    if (v == null) return;
    await v.pause();
    setState(() {
      _progress = 0;
      _error = null;
    });
    VideoAnalyzer? analyzer;
    try {
      analyzer = await VideoAnalyzer.load();
      final r = await analyzer.analyze(
        _path,
        durationMs: v.value.duration.inMilliseconds,
        line: _line,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) {
        setState(() {
          _in = r.nIn;
          _out = r.nOut;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Қате: $e');
    } finally {
      analyzer?.close();
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _save() async {
    await widget.store.add(CountEntry(
      time: DateTime.now(),
      source: _name.isEmpty ? 'қолмен' : _name,
      nIn: _in,
      nOut: _out,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return Scaffold(
      appBar: AppBar(title: const Text('Жаңа санау')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (v == null)
              FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.video_library),
                label: const Text('Бейне таңдау'),
              )
            else ...[
              AspectRatio(
                aspectRatio: v.value.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, c) => Stack(
                    children: [
                      Positioned.fill(child: VideoPlayer(v)),
                      Positioned.fill(
                        child: GateLineEditor(
                          line: _line,
                          onChanged: (l) => setState(() => _line = l),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Қызыл сызықтың екі ұшын сүйреп, қақпаға қойыңыз '
                  '(көлденең, тік немесе қиғаш). Көрсеткі жаққа өту = кірді.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('Бағытты ауыстыру (кірді ↔ шықты)'),
                value: _line.invert,
                onChanged: (x) => setState(() => _line = _line.copyWith(invert: x)),
              ),
              if (_progress != null)
                LinearProgressIndicator(value: _progress)
              else
                OutlinedButton.icon(
                  onPressed: _auto,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Автоматты санау'),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              IconButton(
                iconSize: 40,
                icon: Icon(
                    v.value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () => setState(() =>
                    v.value.isPlaying ? v.pause() : v.play()),
              ),
            ],
            const SizedBox(height: 8),
            Text('Баланс: ${_in - _out}',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CounterButton(
                    label: 'Кірді',
                    value: _in,
                    onAdd: () => setState(() => _in++),
                    onSub: () => setState(() => _in = _in > 0 ? _in - 1 : 0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CounterButton(
                    label: 'Шықты',
                    value: _out,
                    onAdd: () => setState(() => _out++),
                    onSub: () =>
                        setState(() => _out = _out > 0 ? _out - 1 : 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Автоматты нәтижені қолмен түзетуге болады.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Сақтау'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.label,
    required this.value,
    required this.onAdd,
    required this.onSub,
  });

  final String label;
  final int value;
  final VoidCallback onAdd;
  final VoidCallback onSub;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(label),
              Text('$value',
                  style: Theme.of(context).textTheme.displaySmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton.outlined(
                      onPressed: onSub, icon: const Icon(Icons.remove)),
                  IconButton.filled(
                      onPressed: onAdd, icon: const Icon(Icons.add)),
                ],
              ),
            ],
          ),
        ),
      );
}
