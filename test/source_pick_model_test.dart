import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';

Game _game(String name, int size) => Game(
      title: name,
      url: 'https://exemplo/$name',
      size: size,
      consoleId: 'snes',
    );

SourcePick _pick(String name, int size, {bool uncertain = false}) => SourcePick(
      gameId: 'snes/$name',
      title: name,
      filename: name,
      size: size,
      sourceId: 'listagem',
      reason: 'escolhido pela sua região preferida',
      uncertain: uncertain,
      game: _game(name, size),
    );

void main() {
  test('totalBytes soma o tamanho de todas as escolhas', () {
    final plan = BatchPlan(picks: [_pick('a.zip', 1000), _pick('b.zip', 2400)]);

    expect(plan.totalBytes, 3400);
  });

  test('totalBytes é zero num plano sem escolha', () {
    const plan = BatchPlan();

    expect(plan.totalBytes, 0);
    expect(plan.isEmpty, isTrue);
  });

  test('uncertainCount conta só as escolhas marcadas como incertas', () {
    final plan = BatchPlan(picks: [
      _pick('a.zip', 10),
      _pick('b.zip', 10, uncertain: true),
      _pick('c.zip', 10, uncertain: true),
    ]);

    expect(plan.uncertainCount, 2);
  });

  test('withoutPick tira uma escolha e preserva as falhas', () {
    final plan = BatchPlan(
      picks: [_pick('a.zip', 10), _pick('b.zip', 20)],
      failures: const [PickFailure(gameId: 'snes/c', title: 'C', reason: 'sem fonte')],
    );

    final menor = plan.withoutPick('snes/a.zip');

    expect(menor.picks.map((p) => p.gameId), ['snes/b.zip']);
    expect(menor.failures.single.title, 'C');
    // O plano original não muda: a folha guarda o anterior para desfazer.
    expect(plan.picks.length, 2);
  });

  test('withoutPick de um id que não está no plano devolve o mesmo conteúdo', () {
    final plan = BatchPlan(picks: [_pick('a.zip', 10)]);

    expect(plan.withoutPick('snes/nao-existe').picks.length, 1);
  });

  test('um plano só de falhas não está vazio', () {
    const plan = BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'sem fonte')],
    );

    // Importa porque a folha precisa abrir para explicar por que nada vai
    // ser baixado, em vez de sumir sem dizer nada.
    expect(plan.isEmpty, isFalse);
    expect(plan.picks, isEmpty);
  });
}
