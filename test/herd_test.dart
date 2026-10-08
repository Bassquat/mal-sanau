import 'package:flutter_test/flutter_test.dart';
import 'package:mal_sanau/herd.dart';

void main() {
  test('alive count is untagged plus alive tagged', () {
    final h = Herd();
    h.setUntagged(Species.cow, 10);
    h.addAnimal(Species.cow, 'KZ 1');
    h.addAnimal(Species.cow, 'KZ 2');
    expect(h.alive(Species.cow), 12);
    expect(h.totalAlive, 12);
  });

  test('status change updates the count and keeps the animal', () {
    final h = Herd();
    h.addAnimal(Species.sheep, 'A1');
    h.addAnimal(Species.sheep, 'A2');
    final a = h.animals.first;
    h.setStatus(a, AnimalStatus.sold, note: 'Нұрлан');
    expect(h.alive(Species.sheep), 1);
    expect(h.animals.length, 2);
    expect(a.statusDate, isNotNull);
    h.setStatus(a, AnimalStatus.alive);
    expect(h.alive(Species.sheep), 2);
    expect(a.statusDate, isNull);
  });

  test('duplicate and empty tags are rejected per species', () {
    final h = Herd();
    expect(h.addAnimal(Species.cow, 'X1'), isTrue);
    expect(h.addAnimal(Species.cow, ' X1 '), isFalse);
    expect(h.addAnimal(Species.cow, '  '), isFalse);
    expect(h.addAnimal(Species.horse, 'X1'), isTrue);
  });

  test('import splits lines and commas and skips duplicates', () {
    final h = Herd();
    h.addAnimal(Species.goat, 'G1');
    final n = h.importTags(Species.goat, 'G1\nG2, G3;\n\nG4');
    expect(n, 3);
    expect(h.alive(Species.goat), 4);
  });

  test('json round trip', () {
    final h = Herd();
    h.setUntagged(Species.camel, 3);
    h.addAnimal(Species.cow, 'C1', sex: 'ұрғашы', birthYear: 2021);
    h.setStatus(h.animals.first, AnimalStatus.died, note: 'ауырды');
    final r = Herd.fromJson(h.toJson());
    expect(r.alive(Species.camel), 3);
    expect(r.animals.single.status, AnimalStatus.died);
    expect(r.animals.single.note, 'ауырды');
    expect(r.animals.single.birthYear, 2021);
  });
}
