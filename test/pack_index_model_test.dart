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

  test('decode lê as entradas', () {
    final index = PackIndex.decode(sample);
    expect(index.built, '2026-09-10');
    expect(index.packs.length, 2);
    expect(index.packs.first.games, 2415);
  });

  test('normalize segue a mesma regra do id de console do catálogo', () {
    expect(PackIndex.normalize('Nintendo - Super Nintendo Entertainment System'),
        'nintendo_super_nintendo_entertainment_system');
    expect(PackIndex.normalize('  PlayStation 1!! '), 'playstation_1');
  });

  test('resolve pelo id do pacote', () {
    final index = PackIndex.decode(sample);
    final entry = index.resolve(const PackTarget(
        'nintendo_super_nintendo_entertainment_system', 'Qualquer Nome'));
    expect(entry?.pack, 'nintendo_super_nintendo_entertainment_system');
  });

  test('resolve pelo nome do console normalizado', () {
    final index = PackIndex.decode(sample);
    final entry = index.resolve(const PackTarget(
        'catalogo_do_fulano', 'Nintendo - Super Nintendo Entertainment System'));
    expect(entry?.pack, 'nintendo_super_nintendo_entertainment_system');
  });

  test('resolve por alias, do id e do nome', () {
    final index = PackIndex.decode(sample);
    expect(index.resolve(const PackTarget('snes', 'Meu Set'))?.pack,
        'nintendo_super_nintendo_entertainment_system');
    expect(index.resolve(const PackTarget('qualquer', 'PlayStation 1'))?.pack,
        'sony_playstation');
  });

  test('pack exato ganha de alias de outra entrada', () {
    const colliding = '''
{
  "built": "2026-09-10",
  "packs": [
    {"pack": "outro", "system": "Outro", "games": 1, "aliases": ["snes"]},
    {"pack": "snes", "system": "Snes", "games": 2, "aliases": []}
  ]
}
''';
    final index = PackIndex.decode(colliding);
    expect(index.resolve(const PackTarget('snes', 'Snes'))?.pack, 'snes');
  });

  test('console sem pacote devolve null', () {
    final index = PackIndex.decode(sample);
    expect(index.resolve(const PackTarget('nintendo_switch', 'Nintendo Switch')),
        isNull);
  });

  test('PackTarget tem igualdade por valor, para servir de chave de family', () {
    expect(const PackTarget('a', 'b'), const PackTarget('a', 'b'));
    expect(const PackTarget('a', 'b').hashCode, const PackTarget('a', 'b').hashCode);
    expect(const PackTarget('a', 'b') == const PackTarget('a', 'c'), isFalse);
  });
}
