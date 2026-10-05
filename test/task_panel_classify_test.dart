import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';

GameState _s(String name, GameStatus status) => GameState(game: Game(title: name, url: 'https://x/$name.bin', size: 0, consoleId: 'manual'), status: status);

void main() {
  test('a running network transfer is listed under Downloads, other extracting work stays under Extractions', () {
    final transfer = _s('net', GameStatus.extracting);
    final convert = _s('conv', GameStatus.extracting);
    final tabs = classifyTasks([transfer, convert], transferIds: {transfer.game.gameId});
    expect(tabs.downloading, [transfer]);
    expect(tabs.extracting, [convert]);
  });

  test('a queued transfer is under Queue, a failed one under Failed, and neither under Downloads', () {
    final queued = _s('q', GameStatus.extractionQueued);
    final failed = _s('f', GameStatus.extractionFailed);
    final tabs = classifyTasks([queued, failed], transferIds: {queued.game.gameId, failed.game.gameId});
    expect(tabs.queued, [queued]);
    expect(tabs.failed, [failed]);
    expect(tabs.downloading, isEmpty);
  });
}
