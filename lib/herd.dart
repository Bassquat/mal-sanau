import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum Species {
  cow('Сиыр'),
  sheep('Қой'),
  goat('Ешкі'),
  horse('Жылқы'),
  camel('Түйе');

  const Species(this.label);
  final String label;
}

enum AnimalStatus {
  alive('Тірі'),
  sold('Сатылды'),
  slaughtered('Сойылды'),
  died('Өлді'),
  lost('Жоғалды');

  const AnimalStatus(this.label);
  final String label;
}

/// One animal with an ear tag. Animals without a tag are only counted in
/// [Herd.untagged].
class Animal {
  Animal({
    required this.id,
    required this.species,
    required this.tag,
    this.sex = '',
    this.birthYear,
    this.status = AnimalStatus.alive,
    this.statusDate,
    this.note = '',
  });

  final String id;
  final Species species;
  final String tag;
  String sex;
  int? birthYear;
  AnimalStatus status;
  DateTime? statusDate;
  String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sp': species.name,
        'tag': tag,
        'sex': sex,
        'by': birthYear,
        'st': status.name,
        'sd': statusDate?.millisecondsSinceEpoch,
        'n': note,
      };

  static Animal fromJson(Map<String, dynamic> j) => Animal(
        id: j['id'] as String,
        species: Species.values.byName(j['sp'] as String),
        tag: j['tag'] as String,
        sex: (j['sex'] as String?) ?? '',
        birthYear: j['by'] as int?,
        status: AnimalStatus.values.byName(j['st'] as String),
        statusDate: j['sd'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['sd'] as int),
        note: (j['n'] as String?) ?? '',
      );
}

/// The farm's registered livestock. Alive count per species is the untagged
/// number typed by hand plus the alive animals that have an ear tag. Animals
/// are never deleted: a status change keeps the history.
class Herd {
  Herd({Map<Species, int>? untagged, List<Animal>? animals})
      : untagged = untagged ?? {},
        animals = animals ?? [];

  final Map<Species, int> untagged;
  final List<Animal> animals;

  int tagged(Species s) => animals
      .where((a) => a.species == s && a.status == AnimalStatus.alive)
      .length;

  int alive(Species s) => (untagged[s] ?? 0) + tagged(s);

  int get totalAlive => Species.values.fold(0, (n, s) => n + alive(s));

  void setUntagged(Species s, int n) => untagged[s] = n < 0 ? 0 : n;

  bool hasTag(Species s, String tag) =>
      animals.any((a) => a.species == s && a.tag == tag);

  /// Adds an animal; returns false for an empty or duplicate tag.
  bool addAnimal(Species s, String tag, {String sex = '', int? birthYear}) {
    final t = tag.trim();
    if (t.isEmpty || hasTag(s, t)) return false;
    animals.add(Animal(
      id: '${DateTime.now().microsecondsSinceEpoch}-${animals.length}',
      species: s,
      tag: t,
      sex: sex,
      birthYear: birthYear,
    ));
    return true;
  }

  /// Adds tags from pasted text, one per line (commas and semicolons also
  /// split). Returns how many new animals were added.
  int importTags(Species s, String text) {
    var added = 0;
    for (final part in text.split(RegExp(r'[\n,;]'))) {
      if (addAnimal(s, part)) added++;
    }
    return added;
  }

  void setStatus(Animal a, AnimalStatus st,
      {DateTime? when, String note = ''}) {
    a.status = st;
    a.statusDate = st == AnimalStatus.alive ? null : (when ?? DateTime.now());
    if (note.isNotEmpty) a.note = note;
  }

  Map<String, dynamic> toJson() => {
        'u': {for (final e in untagged.entries) e.key.name: e.value},
        'a': [for (final a in animals) a.toJson()],
      };

  static Herd fromJson(Map<String, dynamic> j) => Herd(
        untagged: {
          for (final e in (j['u'] as Map<String, dynamic>).entries)
            Species.values.byName(e.key): e.value as int,
        },
        animals: [
          for (final a in j['a'] as List)
            Animal.fromJson(a as Map<String, dynamic>),
        ],
      );
}

class HerdStore {
  static const _key = 'herd_v1';

  Future<Herd> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return Herd();
      return Herd.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Herd();
    }
  }

  Future<void> save(Herd h) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(h.toJson()));
  }
}
