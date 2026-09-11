import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';

PackGridEntry _e(String title, {bool comFonte = true, String? id}) => PackGridEntry(
      game: PackGame(id: id ?? 'snes/${title.toLowerCase()}', title: title, dumps: const []),
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

  test('títulos iguais saem sempre na mesma ordem, desempatados pelo id', () {
    // Todo outro teste de ordenação usa títulos distintos, então `byTitle != 0`
    // é sempre verdadeiro e o ramo do desempate nunca roda. Sem este caso,
    // apagar o desempate ou invertê-lo não deixa nenhum teste vermelho.
    //
    // As duas chamadas são o ponto: a entrada vai nas duas ordens possíveis e a
    // saída tem que ser a mesma. Uma chamada só passaria por acaso, porque em
    // lista de dois elementos o `sort` do Dart cai em inserção, que preserva a
    // ordem de entrada quando o comparador devolve 0.
    final usa = _e('Final Fantasy', id: 'snes/ff-usa');
    final eur = _e('Final Fantasy', id: 'snes/ff-eur');

    expect(filterPackEntries([usa, eur], '').map((e) => e.game.id), ['snes/ff-eur', 'snes/ff-usa']);
    expect(filterPackEntries([eur, usa], '').map((e) => e.game.id), ['snes/ff-eur', 'snes/ff-usa']);
  });

  test('espaço em volta da busca não conta', () {
    final saida = filterPackEntries([_e('Super Metroid')], '  metroid  ');

    expect(saida.length, 1);
  });

  test('a seleção devolve as entradas na ordem da lista, não na ordem em que foram marcadas', () {
    final entradas = [_e('Chrono Trigger'), _e('EarthBound'), _e('Super Metroid')];

    final saida = entriesForSelection(entradas, {entradas[2].selectionKey, entradas[0].selectionKey});

    expect(saida.map((e) => e.game.title), ['Chrono Trigger', 'Super Metroid']);
  });

  test('chave que não existe mais no pacote é ignorada, sem explodir', () {
    // Acontece quando o pacote é republicado com um slug diferente enquanto a
    // seleção do usuário ainda aponta para o antigo.
    expect(entriesForSelection([_e('Chrono Trigger')], {'pack:snes/jogo-que-sumiu'}), isEmpty);
  });

  test('chave de MODO FONTE não traz entrada de pack nenhuma', () {
    expect(entriesForSelection([_e('Chrono Trigger')], {'snes/Chrono Trigger (USA).zip'}), isEmpty);
  });

  test('em MODO PACK só as chaves com prefixo pack: contam', () {
    final saida = selectionKeysFor(
      {'pack:snes/chrono-trigger', 'snes/Chrono Trigger (USA).zip'},
      pack: true,
    );

    expect(saida, {'pack:snes/chrono-trigger'});
  });

  test('em MODO FONTE só as chaves sem prefixo contam', () {
    final saida = selectionKeysFor(
      {'pack:snes/chrono-trigger', 'snes/Chrono Trigger (USA).zip'},
      pack: false,
    );

    expect(saida, {'snes/Chrono Trigger (USA).zip'});
  });

  test('seleção vazia devolve conjunto vazio nos dois modos', () {
    expect(selectionKeysFor(const {}, pack: true), isEmpty);
    expect(selectionKeysFor(const {}, pack: false), isEmpty);
  });
}
