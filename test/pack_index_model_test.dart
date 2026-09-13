import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/pack_index_model.dart';

void main() {
  const sample = '''
{
  "built": "2026-09-10",
  "packs": [
    {
      "pack": "nintendo_super_nintendo_entertainment_system",
      "system": "Nintendo - Super Nintendo Entertainment System",
      "games": 2415,
      "aliases": ["super_nintendo", "snes", "super_famicom", "sfc"]
    },
    {
      "pack": "sony_playstation",
      "system": "Sony - PlayStation",
      "games": 4000,
      "aliases": ["playstation_1", "playstation", "ps1", "psx"]
    }
  ]
}
''';

  test('decode reads the entries', () {
    final index = PackIndex.decode(sample);
    expect(index.built, '2026-09-10');
    expect(index.packs.length, 2);
    expect(index.packs.first.games, 2415);
  });

  test('normalize follows the catalog console-id rule', () {
    expect(PackIndex.normalize('Nintendo - Super Nintendo Entertainment System'),
        'nintendo_super_nintendo_entertainment_system');
    expect(PackIndex.normalize('  PlayStation 1!! '), 'playstation_1');
  });

  test('resolves by pack id', () {
    final index = PackIndex.decode(sample);
    final entry = index.resolve(const PackTarget(
        'nintendo_super_nintendo_entertainment_system', 'Any Name'));
    expect(entry?.pack, 'nintendo_super_nintendo_entertainment_system');
  });

  test('resolves by the normalized console name', () {
    final index = PackIndex.decode(sample);
    final entry = index.resolve(const PackTarget(
        'acme_catalog', 'Nintendo - Super Nintendo Entertainment System'));
    expect(entry?.pack, 'nintendo_super_nintendo_entertainment_system');
  });

  test('resolves by alias, from id and from name', () {
    final index = PackIndex.decode(sample);
    expect(index.resolve(const PackTarget('snes', 'My Set'))?.pack,
        'nintendo_super_nintendo_entertainment_system');
    expect(index.resolve(const PackTarget('any', 'PlayStation 1'))?.pack,
        'sony_playstation');
  });

  test('an exact pack beats another entry alias regardless of order', () {
    const colliding = '''
{
  "built": "2026-09-10",
  "packs": [
    {"pack": "other", "system": "Other", "games": 1, "aliases": ["snes"]},
    {"pack": "snes", "system": "Snes", "games": 2, "aliases": []}
  ]
}
''';
    final index = PackIndex.decode(colliding);
    expect(index.resolve(const PackTarget('snes', 'Snes'))?.pack, 'snes');

    // Same assertion with the entries reversed: the guarantee comes from
    // resolve scanning every pack before any alias, not from index order.
    const reversed = '''
{
  "built": "2026-09-10",
  "packs": [
    {"pack": "snes", "system": "Snes", "games": 2, "aliases": []},
    {"pack": "other", "system": "Other", "games": 1, "aliases": ["snes"]}
  ]
}
''';
    expect(
        PackIndex.decode(reversed).resolve(const PackTarget('snes', 'Snes'))?.pack,
        'snes');
  });

  test('a console without a pack returns null', () {
    final index = PackIndex.decode(sample);
    expect(index.resolve(const PackTarget('nintendo_switch', 'Nintendo Switch')),
        isNull);
  });

  test('PackTarget has value equality, to serve as a family key', () {
    expect(const PackTarget('a', 'b'), const PackTarget('a', 'b'));
    expect(const PackTarget('a', 'b').hashCode, const PackTarget('a', 'b').hashCode);
    expect(const PackTarget('a', 'b') == const PackTarget('a', 'c'), isFalse);
  });
}
