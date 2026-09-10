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
      "id": "nintendo_super_nintendo_entertainment_system/chrono-trigger",
      "title": "Chrono Trigger",
      "dumps": [
        {"name": "Chrono Trigger (USA)", "crc": "2d206bf7", "sha1": "abc", "serial": null, "region": "USA"},
        {"name": "Chrono Trigger (Japan)", "crc": "1f2e3d4c"}
      ],
      "cover": "https://example.invalid/cover.png",
      "synopsis": "Um RPG.",
      "genre": "Role-Playing",
      "developer": "Square",
      "publisher": "Square",
      "year": 1995
    },
    {
      "id": "nintendo_super_nintendo_entertainment_system/sem-nada",
      "title": "Sem Nada",
      "dumps": []
    }
  ]
}
''';

  test('decode lê o pacote inteiro', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.pack, 'nintendo_super_nintendo_entertainment_system');
    expect(pack.system, 'Nintendo - Super Nintendo Entertainment System');
    expect(pack.built, '2026-09-10');
    expect(pack.games.length, 2);
  });

  test('CRC e SHA1 são normalizados para maiúsculas', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.games.first.dumps.first.crc, '2D206BF7');
    expect(pack.games.first.dumps.first.sha1, 'ABC');
    expect(pack.games.first.dumps[1].sha1, isNull);
  });

  test('region é lida como veio e é opcional', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.games.first.dumps.first.region, 'USA');
    expect(pack.games.first.dumps[1].region, isNull);
  });

  test('campos opcionais ausentes viram null e dumps vazio é permitido', () {
    final pack = MetadataPack.decode(sample);
    final game = pack.games[1];
    expect(game.cover, isNull);
    expect(game.synopsis, isNull);
    expect(game.year, isNull);
    expect(game.dumps, isEmpty);
  });

  test('toJson omite os nulos e sobrevive ao round trip', () {
    final pack = MetadataPack.decode(sample);
    final round = MetadataPack.decode(jsonEncode(pack.toJson()));
    expect(round.games[1].toJson().containsKey('cover'), isFalse);
    expect(round.games.first.dumps.first.crc, '2D206BF7');
    expect(round.games.first.year, 1995);
    expect(round.games.length, 2);
  });

  test('byCrc indexa todos os dumps do pacote', () {
    final pack = MetadataPack.decode(sample);
    expect(pack.byCrc['2D206BF7']?.title, 'Chrono Trigger');
    expect(pack.byCrc['1F2E3D4C']?.title, 'Chrono Trigger');
    expect(pack.byCrc['DEADBEEF'], isNull);
  });
}
