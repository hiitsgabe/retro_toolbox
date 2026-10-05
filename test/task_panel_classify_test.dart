import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';

GameState _s(String name, GameStatus status, {bool transfer = false, bool done = false}) =>
    GameState(game: Game(title: name, url: 'https://x/$name.bin', size: 0, consoleId: 'manual'), status: status, isTransfer: transfer, hasJustCompleted: done);

void main() {
  test('a running network transfer is listed under Downloads, other extracting work stays under Extractions', () {
    final transfer = _s('net', GameStatus.extracting, transfer: true);
    final convert = _s('conv', GameStatus.extracting);
    final tabs = classifyTasks([transfer, convert]);
    expect(tabs.downloading, [transfer]);
    expect(tabs.extracting, [convert]);
  });

  test('a queued transfer is under Queue, a failed one under Failed, and neither under Downloads', () {
    final queued = _s('q', GameStatus.extractionQueued, transfer: true);
    final failed = _s('f', GameStatus.downloadFailed, transfer: true);
    final tabs = classifyTasks([queued, failed]);
    expect(tabs.queued, [queued]);
    expect(tabs.failed, [failed]);
    expect(tabs.downloading, isEmpty);
  });

  test('a finished transfer is under Completed', () {
    final done = _s('d', GameStatus.downloaded, transfer: true, done: true);
    expect(classifyTasks([done]).completed, [done]);
  });

  test('game downloads and extractions are filed as before', () {
    final dl = _s('dl', GameStatus.downloading);
    final paused = _s('p', GameStatus.downloadPaused);
    final dlQ = _s('dq', GameStatus.downloadQueued);
    final ex = _s('ex', GameStatus.extracting);
    final exQ = _s('eq', GameStatus.extractionQueued);
    final done = _s('c', GameStatus.extracted, done: true);
    final failed = _s('f', GameStatus.extractionFailed);
    final tabs = classifyTasks([dl, paused, dlQ, ex, exQ, done, failed]);
    expect(tabs.downloading, [dl, paused, dlQ]);
    expect(tabs.extracting, [ex, exQ]);
    expect(tabs.queued, [dlQ, exQ]);
    expect(tabs.completed, [done]);
    expect(tabs.failed, [failed]);
  });
}
