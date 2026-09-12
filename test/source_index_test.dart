import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_index.dart';

PackGame _pg(String id, String dumpName) => PackGame(
      id: id,
      title: dumpName,
      dumps: [PackDump(name: dumpName)],
    );

PackMatcher _matcher() => PackMatcher(MetadataPack(
      pack: 'snes',
      system: 'Super Nintendo',
      built: '2026-01-01',
      games: [
        _pg('snes/chrono-trigger', 'Chrono Trigger (USA)'),
        _pg('snes/super-metroid', 'Super Metroid (USA)'),
        _pg('snes/earthbound', 'EarthBound (USA)'),
      ],
    ));

SourceFile _f(String filename, {int size = 1024}) =>
    (filename: filename, sourceId: 'listagem', size: size, url: null);

void main() {
  test('cada arquivo casado entra na lista do jogo dele', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Chrono Trigger (USA).zip'),
      _f('Super Metroid (USA).zip'),
    ]);

    expect(index.sourcesFor('snes/chrono-trigger').single.filename, 'Chrono Trigger (USA).zip');
    expect(index.sourcesFor('snes/super-metroid').single.filename, 'Super Metroid (USA).zip');
    expect(index.hasSource('snes/earthbound'), isFalse);
  });

  test('duas versões do mesmo jogo ficam juntas, na ordem da listagem', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Chrono Trigger (USA).zip'),
      _f('Chrono Trigger (Europe).zip'),
    ]);

    expect(
      index.sourcesFor('snes/chrono-trigger').map((s) => s.filename),
      ['Chrono Trigger (USA).zip', 'Chrono Trigger (Europe).zip'],
    );
  });

  test('a confiança de cada fonte vem do tier daquele arquivo', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Chrono Trigger (USA).zip'),   // nome exato
      _f('Chrono Triggr (USA).zip'),    // erro de digitação, cai no fuzzy
    ]);

    final fontes = index.sourcesFor('snes/chrono-trigger');
    expect(fontes.map((s) => s.confidence),
        [MatchConfidence.likely, MatchConfidence.guess]);
  });

  test('o tamanho e a fonte de origem sobrevivem à travessia', () {
    final index = SourceIndex.build(_matcher(), [_f('Chrono Trigger (USA).zip', size: 4096)]);

    final fonte = index.sourcesFor('snes/chrono-trigger').single;
    expect(fonte.size, 4096);
    expect(fonte.sourceId, 'listagem');
  });

  test('arquivo que não casa com jogo nenhum vira um não reconhecido', () {
    final index = SourceIndex.build(_matcher(), [_f('Jogo Que Nao Existe (USA).zip')]);

    expect(index.unmatched, ['Jogo Que Nao Existe (USA).zip']);
    expect(index.matchedGameCount, 0);
  });

  test('o que não é ROM é ignorado, e não conta como não reconhecido', () {
    // A listagem do archive.org vem cheia de .txt, .png e .xml de índice.
    // Chamar isso de "não reconhecido" mentiria na faixa da Task 12.
    final index = SourceIndex.build(_matcher(), [
      _f('leiame.txt'),
      _f('Chrono Trigger (USA).zip'),
    ]);

    expect(index.unmatched, isEmpty);
    expect(index.matchedGameCount, 1);
  });

  test('jogo sem fonte devolve lista vazia, nunca nulo', () {
    final index = SourceIndex.build(_matcher(), const []);

    expect(index.sourcesFor('snes/earthbound'), isEmpty);
    expect(index.sourcesFor('id/que/nao/existe'), isEmpty);
  });
}
