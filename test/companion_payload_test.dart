import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/dual_screen/companion_payload.dart';

Game game(String title) => Game(title: title, url: 'https://x/$title.zip', size: 1, consoleId: 'snes');

GameState st(String title, GameStatus status, {bool done = false, bool bar = false, double progress = 0}) =>
    GameState(game: game(title), status: status, hasJustCompleted: done, showProgressBar: bar, currentProgress: progress);

List<Map<String, dynamic>> rows(Iterable<GameState> states) => (jsonDecode(jsonEncode(tasksPayload(states)))['tasks'] as List).cast<Map<String, dynamic>>();

void main() {
  test('the details payload carries the whole game', () {
    final g = game('Chrono Trigger');
    final payload = jsonDecode(jsonEncode(detailsPayload(g))) as Map<String, dynamic>;
    expect(payload['mode'], 'details');
    expect(Game.fromJson(payload['game']).toJson(), g.toJson());
  });

  test('tasks go active, queued, failed, done, each once', () {
    final r = rows([
      st('done', GameStatus.extracted, done: true),
      st('old', GameStatus.extracted),
      st('failed', GameStatus.downloadFailed),
      st('unzip', GameStatus.extracting),
      st('waiting', GameStatus.downloadQueued),
      st('ready', GameStatus.ready),
      st('dl', GameStatus.downloading),
    ]);
    expect([for (final x in r) x['title']], ['waiting', 'dl', 'unzip', 'failed', 'done']);
    expect([for (final x in r) x['state']], ['active', 'active', 'active', 'failed', 'done']);
    expect(r[0]['status'], 'Dl. Queued');
    expect(r[3]['status'], 'Download Failed');
  });

  test('progress shows only with a progress bar', () {
    final r = rows([
      st('a', GameStatus.downloading, bar: true, progress: 0.4),
      st('b', GameStatus.downloading, progress: 0.4),
    ]);
    expect(r[0]['progress'], 0.4);
    expect(r[1]['progress'], isNull);
    expect(r[1].containsKey('progress'), isTrue);
  });

  test('at most 30 rows', () {
    expect(rows([for (var i = 0; i < 40; i++) st('g$i', GameStatus.downloading)]), hasLength(30));
    expect(tasksPayload(const [])['mode'], 'tasks');
  });
}
