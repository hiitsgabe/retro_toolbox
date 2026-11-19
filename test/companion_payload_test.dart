import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/dual_screen/companion_payload.dart';

Game game(String title) => Game(title: title, url: 'https://x/$title.zip', size: 1, consoleId: 'snes');

GameState st(String title, GameStatus status, {bool done = false, bool bar = false, double progress = 0}) =>
    GameState(game: game(title), status: status, hasJustCompleted: done, showProgressBar: bar, currentProgress: progress);

Map<String, dynamic> wire(Map<String, dynamic> payload) => jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

List<String> titles(Map<String, dynamic> payload, String tab) => [for (final r in payload['tabs'][tab] as List) Game.fromJson(r['game']).title];

void main() {
  test('the details payload carries the whole game, and its state when given', () {
    final g = game('Chrono Trigger');
    final payload = wire(detailsPayload(g));
    expect(payload['mode'], 'details');
    expect(Game.fromJson(payload['game']).toJson(), g.toJson());
    expect(payload['launchbox'], isNull);
    expect(payload.containsKey('state'), isFalse);
    expect(detailsPayload(g, launchboxVersion: '"e1"')['launchbox'], '"e1"');

    final withState = wire(detailsPayload(g,
        state: GameState(game: g, status: GameStatus.downloadFailed, availableActions: const {GameAction.retryDownload}, errorMessage: 'HTTP 404')));
    final back = gameStateFromJson(withState['state']);
    expect(back.status, GameStatus.downloadFailed);
    expect(back.statusText, 'Download Failed');
    expect(back.availableActions, {GameAction.retryDownload});
    expect(back.errorMessage, 'HTTP 404');
  });

  test('a state goes over the wire with what a row draws from it', () {
    final s = GameState(
      game: const Game(title: 'Zelda', url: 'https://x/z.zip', size: 4096, consoleId: 'snes', details: GameDetails(boxart: 'https://x/z.png')),
      status: GameStatus.downloading,
      availableActions: const {GameAction.pause, GameAction.cancel},
      isInteractable: false,
      showProgressBar: true,
      currentProgress: 0.25,
      networkSpeed: 1024,
      timeRemaining: const Duration(seconds: 90),
      isTransfer: true,
      movingToDestination: true,
      hasJustCompleted: true,
    );
    final back = gameStateFromJson(wire(gameStateJson(s)));
    expect(back.game.toJson(), s.game.toJson());
    expect(back.game.boxart, 'https://x/z.png');
    expect(back.availableActions, s.availableActions);
    expect(
      (back.status, back.isInteractable, back.showProgressBar, back.currentProgress, back.networkSpeed, back.timeRemaining),
      (s.status, false, true, 0.25, 1024.0, const Duration(seconds: 90)),
    );
    expect((back.isTransfer, back.movingToDestination, back.hasJustCompleted), (true, true, true));
  });

  test('an action name the companion does not know is skipped', () {
    final json = wire(gameStateJson(GameState(game: game('a'), status: GameStatus.ready, availableActions: const {GameAction.download})));
    json['actions'] = ['download', 'teleport'];
    expect(gameStateFromJson(json).availableActions, {GameAction.download});
  });

  test('tasks fill the Task Manager tabs as classifyTasks does', () {
    final payload = wire(tasksPayload([
      st('done', GameStatus.extracted, done: true),
      st('old', GameStatus.extracted),
      st('failed', GameStatus.downloadFailed),
      st('unzip', GameStatus.extracting),
      st('waiting', GameStatus.downloadQueued),
      st('ready', GameStatus.ready),
      st('dl', GameStatus.downloading),
    ]));
    expect(payload['mode'], 'tasks');
    expect(titles(payload, 'downloading'), ['dl']);
    expect(titles(payload, 'extracting'), ['unzip']);
    expect(titles(payload, 'queued'), ['waiting']);
    expect(titles(payload, 'completed'), ['done']);
    expect(titles(payload, 'failed'), ['failed']);
  });

  test('rows say which games are favourites', () {
    final payload = wire(tasksPayload([st('a', GameStatus.downloading), st('b', GameStatus.downloading)], isFavorite: (id) => id == 'snes/a.zip'));
    expect([for (final r in payload['tabs']['downloading'] as List) r['favorite']], [true, false]);
  });

  test('at most 200 rows a tab', () {
    final payload = tasksPayload([for (var i = 0; i < 250; i++) st('g$i', GameStatus.downloadQueued)]);
    expect(payload['tabs']['queued'], hasLength(maxTaskRowsPerTab));
  });

  test('requests name the game and the action', () {
    expect(gameActionRequest('snes/a.zip', GameAction.download), {'kind': 'game', 'gameId': 'snes/a.zip', 'action': 'download'});
    expect(favoriteRequest('snes/a.zip'), {'kind': 'favorite', 'gameId': 'snes/a.zip'});
  });
}
