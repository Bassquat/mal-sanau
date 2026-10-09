import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'analyzer.dart';
import 'count_overlay.dart';
import 'gate_line.dart';
import 'herd.dart';
import 'herd_page.dart';
import 'live_page.dart';
import 'stepper.dart';
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
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final e = await _store.load();
    if (mounted) setState(() => _entries = e);
  }

  Future<void> _liveCount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LivePage(store: _store)),
    );
    _reload();
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

  Widget _history() => _entries.isEmpty
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
        );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_tab == 0 ? 'Мал санау' : 'Менің малым')),
        body: _tab == 0 ? _history() : const HerdTab(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.history), label: 'Санау'),
            NavigationDestination(icon: Icon(Icons.pets), label: 'Мал'),
          ],
        ),
        floatingActionButton: _tab == 0
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'live',
                    onPressed: _liveCount,
                    icon: const Icon(Icons.videocam),
                    label: const Text('Тікелей санау'),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'video',
                    onPressed: _newCount,
                    icon: const Icon(Icons.video_library),
                    label: const Text('Бейне санау'),
                  ),
                ],
              )
            : null,
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
  bool _dragging = false;
  double? _progress;
  String? _error;
  int? _registered;
  final List<FrameInfo> _frames = [];
  final List<CountEvent> _events = [];
  int _seqIn = 0, _seqOut = 0;

  // Dense-crowd mode: counts the picture flow across the line instead of
  // tracking each animal; _share is the frame share one animal covers.
  bool _flow = false;
  double _share = defaultAnimalShare;
  double _flowIn = 0, _flowOut = 0;
  bool _analysed = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getDouble('flow_share');
      if (v != null && v > 0 && mounted) setState(() => _share = v);
    });
    HerdStore().load().then((h) {
      if (mounted) setState(() => _registered = h.totalAlive);
    });
  }

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
    _frames.clear();
    _events.clear();
    _seqIn = _seqOut = 0;
    _flowIn = _flowOut = 0;
    setState(() {
      _analysed = false;
      _progress = 0;
      _error = null;
      _in = 0;
      _out = 0;
    });
    // The video plays (silently) while it is being analysed, so the marks on
    // the animals follow the picture and the total is ready when it ends.
    await v.setVolume(0);
    await v.seekTo(Duration.zero);
    await v.play();
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
        flow: _flow,
        animalShare: _share,
        onDecoderBusy: () async {
          await v.pause();
        },
        onFrame: (f) {
          if (!mounted) return;
          _frames.add(f);
          for (final c in f.crossings) {
            _events.add(CountEvent(
                f.timeMs, c.$1, c.$2, c.$2 > 0 ? ++_seqIn : ++_seqOut, c.$3, c.$4));
          }
          _flowIn = f.flowIn;
          _flowOut = f.flowOut;
          setState(() {
            _in = f.nIn;
            _out = f.nOut;
          });
        },
      );
      if (mounted) {
        setState(() {
          _in = r.nIn;
          _out = r.nOut;
          _analysed = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Қате: $e');
    } finally {
      analyzer?.close();
      if (mounted) setState(() => _progress = null);
    }
  }

  /// The user knows how many animals really went in: derive the area one
  /// animal covers from it and keep it for next time.
  Future<void> _calibrate() async {
    if (_flowIn <= 0) return;
    final n = await askNumber(context, _in, title: 'Нақты неше мал кірді?');
    if (n == null || n <= 0) return;
    final share = _flowIn / n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('flow_share', share);
    setState(() {
      _share = share;
      _in = n;
      _out = (_flowOut / share).round();
    });
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
        physics: _dragging ? const NeverScrollableScrollPhysics() : null,
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
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.42),
                  child: AspectRatio(
                aspectRatio: v.value.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, c) => Stack(
                    children: [
                      Positioned.fill(child: VideoPlayer(v)),
                      Positioned.fill(
                        child: ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: v,
                          builder: (_, val, __) => CountOverlay(
                            frames: _frames,
                            events: _events,
                            positionMs: val.position.inMilliseconds,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: GateLineEditor(
                          line: _line,
                          onChanged: (l) => setState(() => _line = l),
                          onDragging: (d) => setState(() => _dragging = d),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Қызыл сызықтың 1 және 2 нүктелерін сүйреп, қақпаға қойыңыз. '
                        'Көрсеткі жаққа өту = кірді.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _line =
                          GateLine.initial.copyWith(invert: _line.invert)),
                      child: const Text('Қалпына келтіру'),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('Бағытты ауыстыру (кірді ↔ шықты)'),
                value: _line.invert,
                onChanged: (x) => setState(() => _line = _line.copyWith(invert: x)),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('Тығыз топ (ағын әдісі)'),
                subtitle: const Text(
                    'Қойлар бір-біріне тығыз тұрса. Санау шамамен болады.'),
                value: _flow,
                onChanged: _progress != null ? null : (x) => setState(() => _flow = x),
              ),
              if (_progress != null)
                LinearProgressIndicator(value: _progress)
              else
                OutlinedButton.icon(
                  onPressed: _auto,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Автоматты санау'),
                ),
              if (_flow && _analysed && _progress == null)
                TextButton.icon(
                  onPressed: _calibrate,
                  icon: const Icon(Icons.tune),
                  label: const Text('Нақты санмен калибрлеу'),
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
            if (_in + _out > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    TallyMarks(count: _in, color: Colors.green.shade700),
                    TallyMarks(count: _out, color: Colors.red.shade700),
                  ],
                ),
              ),
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
                    onChanged: (n) => setState(() => _in = n),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CounterButton(
                    label: 'Шықты',
                    value: _out,
                    onChanged: (n) => setState(() => _out = n),
                  ),
                ),
              ],
            ),
            if ((_registered ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Text('Тіркелген тірі мал: $_registered, санау балансы: ${_in - _out}',
                  style: const TextStyle(color: Colors.grey)),
            ],
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
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(label),
              const SizedBox(height: 4),
              FittedBox(
                  child: CountStepper(value: value, onChanged: onChanged)),
            ],
          ),
        ),
      );
}
