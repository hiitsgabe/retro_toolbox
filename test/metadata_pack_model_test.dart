import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

void main() {
  const sample = '''
{
  "pack": "nintendo_super_nintendo_entertainment_system",
  "system": "Nintendo - Super Nintendo Entertainment System",
  "built": "2026-09-10",
  "games": [
    {
      "id": "nintendo_super_nintendo_entertainment_system/crystal-vanguard",
      "title": "Crystal Vanguard",
      "dumps": [
        {"name": "Crystal Vanguard (USA)", "crc": "2d206bf7", "sha1": "abc", "serial": null, "region": "USA"},
        {"name": "Crystal Vanguard (Japan)", "crc": "1f2e3d4c"}
      ],
      "cover": "https://example.invalid/cover.png",
      "synopsis": "An RPG.",
      "genre": "Role-Playing",
      "developer": "Square",
      "publisher": "Square",
      "year": 1995
    },
    {
      "id": "nintendo_super_nintendo_entertainment_system/sparse-entry",
      "title": "Sparse Entry",
      "dumps": []
    }
  ]
}
''';

  test('decode reads the whole pack', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.pack, 'nintendo_super_nintendo_entertainment_system');
    expect(pack.system, 'Nintendo - Super Nintendo Entertainment System');
    expect(pack.built, '2026-09-10');
    expect(pack.games.length, 2);
  });

  test('CRC and SHA1 are uppercased', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.games.first.dumps.first.crc, '2D206BF7');
    expect(pack.games.first.dumps.first.sha1, 'ABC');
    expect(pack.games.first.dumps[1].sha1, isNull);
  });

  test('region is read as-is and is optional', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.games.first.dumps.first.region, 'USA');
    expect(pack.games.first.dumps[1].region, isNull);
  });

  test('absent optional fields become null and empty dumps is allowed', () {
    final pack = MetadataPack.decode(sample);
    final game = pack.games[1];
    expect(game.cover, isNull);
    expect(game.synopsis, isNull);
    expect(game.year, isNull);
    expect(game.dumps, isEmpty);
  });

  test('toJson omits nulls and survives a round trip', () {
    final pack = MetadataPack.decode(sample);
    final round = MetadataPack.decode(jsonEncode(pack.toJson()));
    expect(round.games[1].toJson().containsKey('cover'), isFalse);
    expect(round.games.first.dumps.first.crc, '2D206BF7');
    expect(round.games.first.year, 1995);
    expect(round.games.length, 2);
  });

  test('byCrc indexes every dump in the pack', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.byCrc['2D206BF7']?.title, 'Crystal Vanguard');
    expect(pack.byCrc['1F2E3D4C']?.title, 'Crystal Vanguard');
    expect(pack.byCrc['DEADBEEF'], isNull);
  });
}
