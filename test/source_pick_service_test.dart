import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';

Game _game(String filename, int size) => Game(
      title: filename.replaceAll('.zip', ''),
      url: 'https://exemplo.org/snes/$filename',
      size: size,
      consoleId: 'snes',
    );

void main() {
  test('cada jogo selecionado vira uma escolha, na mesma ordem', () {
    final plan = planFromGames([
      _game('Chrono Trigger (USA).zip', 4 * 1024 * 1024),
      _game('Super Metroid (USA).zip', 3 * 1024 * 1024),
    ]);

    expect(plan.picks.map((p) => p.filename),
        ['Chrono Trigger (USA).zip', 'Super Metroid (USA).zip']);
    expect(plan.totalBytes, 7 * 1024 * 1024);
  });

  test('a chave e o Game inteiro viajam junto, porque é o que vai para a fila', () {
    final game = _game('Chrono Trigger (USA).zip', 1024);
    final pick = planFromGames([game]).picks.single;

    expect(pick.gameId, game.gameId);
    expect(pick.game, same(game));
    expect(pick.size, 1024);
  });

  test('em MODO FONTE nada é incerto e nada fica de fora', () {
    // A folha existe para mostrar incerteza e falha. Em MODO FONTE ela não
    // tem nenhuma das duas para mostrar, e isso é correto, não é bug: o
    // arquivo que o usuário marcou é o arquivo que ele vai receber.
    final plan = planFromGames([_game('a.zip', 1), _game('b.zip', 2)]);

    expect(plan.uncertainCount, 0);
    expect(plan.failures, isEmpty);
    expect(plan.picks.every((p) => p.reason.isNotEmpty), isTrue);
  });

  test('sem jogo nenhum o plano fica vazio de verdade', () {
    expect(planFromGames(const []).isEmpty, isTrue);
  });
}
