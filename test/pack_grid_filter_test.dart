import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';

PackGridEntry _e(String title, {bool comFonte = true}) => PackGridEntry(
      game: PackGame(id: 'snes/${title.toLowerCase()}', title: title, dumps: const []),
      sources: comFonte
          ? [const MatchedSource(filename: 'a.zip', sourceId: 'listagem', confidence: MatchConfidence.likely, size: 1)]
          : const [],
    );

void main() {
  test('busca vazia devolve tudo', () {
    final saida = filterPackEntries([_e('Super Metroid'), _e('Chrono Trigger')], '');

    expect(saida.length, 2);
  });

  test('a saída sai ordenada por título, não na ordem do pacote', () {
    final saida = filterPackEntries([_e('Super Metroid'), _e('Chrono Trigger'), _e('EarthBound')], '');

    expect(saida.map((e) => e.game.title), ['Chrono Trigger', 'EarthBound', 'Super Metroid']);
  });

  test('a busca ignora caixa e acento', () {
    // `norm` já dobra acento e baixa a caixa desde a fatia 2. Não reimplemente.
    final saida = filterPackEntries([_e('Pokémon Red'), _e('Super Metroid')], 'pokemon');

    expect(saida.single.game.title, 'Pokémon Red');
  });

  test('a busca casa pedaço do meio do título', () {
    final saida = filterPackEntries([_e('The Legend of Zelda'), _e('Super Metroid')], 'zelda');

    expect(saida.single.game.title, 'The Legend of Zelda');
  });

  test('busca sem resultado devolve lista vazia', () {
    final saida = filterPackEntries([_e('Super Metroid')], 'halo');

    expect(saida, isEmpty);
  });

  test('jogo sem fonte continua aparecendo, porque a grade mostra tudo', () {
    // Decisão travada do projeto inteiro: a grade mostra todos os jogos do
    // pacote e marca a exceção. Filtrar por disponibilidade aqui é o erro que
    // esta linha existe para impedir.
    final saida = filterPackEntries([_e('Super Metroid', comFonte: false)], '');

    expect(saida.single.hasSource, isFalse);
  });

  test('espaço em volta da busca não conta', () {
    final saida = filterPackEntries([_e('Super Metroid')], '  metroid  ');

    expect(saida.length, 1);
  });
}
