import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

PackGame _pg(String id, String title) => PackGame(id: id, title: title, dumps: const []);

MatchedSource _src(String filename, {MatchConfidence confidence = MatchConfidence.likely}) =>
    MatchedSource(filename: filename, sourceId: 'listagem', confidence: confidence, size: 1024);

void main() {
  test('sem fonte nenhuma a entrada não está disponível', () {
    final entry = PackGridEntry(game: _pg('snes/chrono-trigger', 'Chrono Trigger'), sources: const []);

    expect(entry.hasSource, isFalse);
    expect(entry.sourceCount, 0);
  });

  test('com pelo menos uma fonte a entrada está disponível', () {
    final entry = PackGridEntry(
      game: _pg('snes/chrono-trigger', 'Chrono Trigger'),
      sources: [_src('Chrono Trigger (USA).zip')],
    );

    expect(entry.hasSource, isTrue);
    expect(entry.sourceCount, 1);
  });

  test('a chave de seleção tem o prefixo pack:, e não colide com gameId', () {
    // Ver "Quarta decisão travada" no topo do plano. `Game.gameId` é
    // 'snes/arquivo.zip' e `PackGame.id` é 'snes/chrono-trigger': os dois
    // começam com letra e têm barra. O prefixo é o que os separa.
    final entry = PackGridEntry(game: _pg('snes/chrono-trigger', 'Chrono Trigger'), sources: const []);

    expect(entry.selectionKey, 'pack:snes/chrono-trigger');
  });

  test('a entrada não inventa confiança própria a partir das fontes', () {
    // Ver "Armadilha de leitura" no topo. Um jogo com uma fonte confirmada e
    // uma no chute continua sendo um jogo só, e o tile dele é igual ao de
    // qualquer outro jogo com fonte.
    final entry = PackGridEntry(
      game: _pg('snes/chrono-trigger', 'Chrono Trigger'),
      sources: [
        _src('a.zip', confidence: MatchConfidence.confirmed),
        _src('b.zip', confidence: MatchConfidence.guess),
      ],
    );

    expect(entry.hasSource, isTrue);
    expect(entry.sourceCount, 2);
    // Se você acabou de escrever `entry.confidence`, apague: não existe e não
    // vai existir.
  });
}
