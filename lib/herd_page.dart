import 'package:flutter/material.dart';

import 'herd.dart';

String fmtDate(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';

/// "Мал" tab: alive count per species, then a per-species page.
class HerdTab extends StatefulWidget {
  const HerdTab({super.key});

  @override
  State<HerdTab> createState() => _HerdTabState();
}

class _HerdTabState extends State<HerdTab> {
  final _store = HerdStore();
  Herd? _herd;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await _store.load();
    if (mounted) setState(() => _herd = h);
  }

  Future<void> _open(Species s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SpeciesPage(species: s, herd: _herd!, store: _store)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final h = _herd;
    if (h == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Барлығы тірі: ${h.totalAlive}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Түрін басып, санын не құлақ сақина нөмірлерін жазыңыз.',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        for (final s in Species.values)
          Card(
            child: ListTile(
              title: Text(s.label),
              subtitle: Text('сақинамен: ${h.tagged(s)}'),
              trailing: Text('${h.alive(s)}',
                  style: Theme.of(context).textTheme.headlineSmall),
              onTap: () => _open(s),
            ),
          ),
      ],
    );
  }
}

class SpeciesPage extends StatefulWidget {
  const SpeciesPage(
      {super.key,
      required this.species,
      required this.herd,
      required this.store});
  final Species species;
  final Herd herd;
  final HerdStore store;

  @override
  State<SpeciesPage> createState() => _SpeciesPageState();
}

class _SpeciesPageState extends State<SpeciesPage> {
  bool _onlyAlive = true;

  Herd get _h => widget.herd;
  Species get _s => widget.species;

  Future<void> _changed() async {
    await widget.store.save(_h);
    if (mounted) setState(() {});
  }

  Future<String?> _ask(String title, {bool multiline = false, String? hint}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: multiline ? 4 : 1,
          maxLines: multiline ? 10 : 1,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Болдырмау')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Сақтау')),
        ],
      ),
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addOne() async {
    final tag = await _ask('Сақина нөмірі', hint: 'мысалы KZ 104 227');
    if (tag == null) return;
    if (_h.addAnimal(_s, tag)) {
      await _changed();
    } else {
      _snack('Нөмір бос не бұрын жазылған');
    }
  }

  Future<void> _paste() async {
    final text = await _ask('Нөмірлер тізімі',
        multiline: true, hint: 'Әр жолға бір нөмір');
    if (text == null) return;
    final n = _h.importTags(_s, text);
    await _changed();
    _snack('Қосылды: $n');
  }

  Future<void> _setStatus(Animal a) async {
    final st = await showModalBottomSheet<AnimalStatus>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('${a.tag}: мәртебесі')),
            for (final s in AnimalStatus.values)
              ListTile(
                leading: Icon(s == a.status
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(s.label),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (st == null || st == a.status) return;
    var note = '';
    if (st != AnimalStatus.alive) {
      note = (await _ask(
              st == AnimalStatus.sold
                  ? 'Кімге сатылды, бағасы (міндетті емес)'
                  : 'Себебі (міндетті емес)')) ??
          '';
    }
    _h.setStatus(a, st, note: note.trim());
    await _changed();
  }

  @override
  Widget build(BuildContext context) {
    final list = _h.animals
        .where((a) =>
            a.species == _s && (!_onlyAlive || a.status == AnimalStatus.alive))
        .toList()
        .reversed
        .toList();
    final u = _h.untagged[_s] ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text('${_s.label}: ${_h.alive(_s)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(child: Text('Сақинасыз (қолмен сан)')),
                  IconButton.outlined(
                      onPressed: () {
                        _h.setUntagged(_s, u - 1);
                        _changed();
                      },
                      icon: const Icon(Icons.remove)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('$u',
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  IconButton.filled(
                      onPressed: () {
                        _h.setUntagged(_s, u + 1);
                        _changed();
                      },
                      icon: const Icon(Icons.add)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                  onPressed: _addOne,
                  icon: const Icon(Icons.add),
                  label: const Text('Нөмір қосу')),
              OutlinedButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Тізімді қою')),
            ],
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Тек тірілерді көрсету'),
            value: _onlyAlive,
            onChanged: (v) => setState(() => _onlyAlive = v),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Сақина нөмірлері әлі жоқ.',
                  style: TextStyle(color: Colors.grey)),
            ),
          for (final a in list)
            ListTile(
              title: Text(a.tag),
              subtitle: Text([
                if (a.statusDate != null) fmtDate(a.statusDate!),
                if (a.note.isNotEmpty) a.note,
              ].join(' · ')),
              trailing: Chip(label: Text(a.status.label)),
              onTap: () => _setStatus(a),
            ),
        ],
      ),
    );
  }
}
