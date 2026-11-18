import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/companion/companion_app.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_group_model.dart';
import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/dual_screen/companion_payload.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';

const _channel = MethodChannel('retro_toolbox/companion');

const _sonic = Game(
  title: 'Sonic The Hedgehog (USA, Europe).zip',
  url: 'https://example.com/sonic.zip',
  size: 3 * 1024 * 1024,
  consoleId: 'md',
  metadata: GameMetadata(displayTitle: 'Sonic The Hedgehog', regions: ['USA']),
  details: GameDetails(boxart: 'https://example.com/sonic.png'),
);

const _streets = Game(
  title: 'Streets of Rage 2 (USA).zip',
  url: 'https://example.com/sor2.zip',
  size: 2 * 1024 * 1024,
  consoleId: 'md',
  metadata: GameMetadata(displayTitle: 'Streets of Rage 2', regions: ['USA']),
  details: GameDetails(launchboxPlatform: 'Sega Genesis', launchboxId: 2),
);

const _streetsLb = LaunchboxGame(
  id: 2,
  name: 'Streets of Rage 2',
  overview: 'Axel and Blaze take back the city from Mr. X.',
);

Widget _image(BuildContext context, String url, {BoxFit fit = BoxFit.cover, Alignment alignment = Alignment.center, Widget? placeholder, Widget? fallback}) => SizedBox(key: ValueKey(url));

void main() {
  late List<String> sent;
  late List<Map<String, dynamic>> requests;

  setUp(() {
    sent = [];
    requests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      sent.add(call.method);
      if (call.method == 'action') requests.add(jsonDecode(call.arguments as String) as Map<String, dynamic>);
      return null;
    });
    CompanionScreen.debugImageBuilder = _image;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    CompanionScreen.debugImageBuilder = null;
  });

  Future<void> start(WidgetTester t,
      {Future<LaunchboxGame?> Function(String platform, int id)? lookup, VoidCallback? invalidate, Size size = const Size(1240, 1080)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(CompanionApp(
      home: CompanionScreen(channel: _channel, lookup: lookup ?? (_, __) async => null, invalidate: invalidate ?? () {}),
    ));
  }

  /// The handler's reply, decoded: an error the handler threw comes back as a
  /// PlatformException, not through the test's exception.
  Future<Object? Function()> send(WidgetTester t, Object payload) async {
    final json = payload is String ? payload : jsonEncode(payload);
    ByteData? reply;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('update', json)),
      (data) => reply = data,
    );
    await t.pumpAndSettle();
    return () => const StandardMethodCodec().decodeEnvelope(reply!);
  }

  void noActions() {
    expect(find.text('Download'), findsNothing);
    expect(find.text('Add to favourites'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  }

  testWidgets('ready is sent once on start', (t) async {
    await start(t);
    await t.pumpAndSettle();
    expect(sent, ['ready']);
    await send(t, detailsPayload(_sonic));
    expect(sent, ['ready']);
  });

  testWidgets('before any payload it shows the empty Task Manager', (t) async {
    await start(t);
    expect(find.text('Task Manager'), findsOneWidget);
    expect(find.text('No active downloads'), findsOneWidget);
    noActions();
  });

  testWidgets('a details payload shows the game, without LaunchBox data', (t) async {
    final asked = <(String, int)>[];
    await start(t, lookup: (p, id) async {
      asked.add((p, id));
      return null;
    });
    await send(t, detailsPayload(_sonic));
    expect(find.text('Sonic The Hedgehog'), findsOneWidget);
    expect(find.text('Task Manager'), findsNothing);
    expect(find.text('About'), findsNothing);
    expect(asked, isEmpty, reason: 'no LaunchBox id, nothing to look up');
    noActions();
  });

  testWidgets('a box set entry is shown by the box name, not its first game', (t) async {
    final box = GameGroup(title: 'Sonic Collection', members: [GameGroup(title: 'Sonic The Hedgehog')]);
    final payload = detailsPayload(_sonic.copyWith(group: box));
    expect((payload['game'] as Map)['metadata']['displayTitle'], 'Sonic The Hedgehog');
    expect(payload['displayTitle'], 'Sonic Collection');
    await start(t);
    await send(t, payload);
    expect(find.text('Sonic Collection'), findsOneWidget);
    expect(find.text('Sonic The Hedgehog'), findsNothing);
  });

  testWidgets('a details payload with a LaunchBox id shows the record from the lookup', (t) async {
    final asked = <(String, int)>[];
    await start(t, lookup: (p, id) async {
      asked.add((p, id));
      return _streetsLb;
    });
    await send(t, detailsPayload(_streets));
    expect(asked, [('Sega Genesis', 2)]);
    expect(find.text('Axel and Blaze take back the city from Mr. X.'), findsOneWidget);
    noActions();
  });

  testWidgets('another LaunchBox import drops the caches and looks the shown game up again', (t) async {
    var invalidated = 0;
    var overview = 'Before the import.';
    final asked = <(String, int)>[];
    await start(
      t,
      lookup: (p, id) async {
        asked.add((p, id));
        return LaunchboxGame(id: id, name: 'Streets of Rage 2', overview: overview);
      },
      invalidate: () => invalidated++,
    );
    await send(t, detailsPayload(_streets, launchboxVersion: '"e1"'));
    expect(find.text('Before the import.'), findsOneWidget);
    final atFirst = invalidated;
    await send(t, detailsPayload(_streets, launchboxVersion: '"e1"'));
    expect((invalidated, asked.length), (atFirst, 1), reason: 'same import, same game: nothing to do');

    overview = 'After the import.';
    await send(t, detailsPayload(_streets, launchboxVersion: '"e2"'));
    expect(invalidated, atFirst + 1);
    expect(asked, hasLength(2));
    expect(find.text('After the import.'), findsOneWidget);

    // Metadata off: the game comes without its LaunchBox id, and the old
    // record must not stay on screen.
    await send(t, detailsPayload(_streets.copyWith(details: const GameDetails()), launchboxVersion: null));
    expect(invalidated, atFirst + 2);
    expect(find.text('After the import.'), findsNothing);
  });

  testWidgets('a lookup that resolves after a newer payload does not replace the newer game', (t) async {
    final slow = Completer<LaunchboxGame?>();
    await start(t, lookup: (_, __) => slow.future);
    await send(t, detailsPayload(_streets));
    await send(t, detailsPayload(_sonic));
    slow.complete(_streetsLb);
    await t.pumpAndSettle();
    expect(find.text('Sonic The Hedgehog'), findsOneWidget);
    expect(find.text('Streets of Rage 2'), findsNothing);
    expect(find.text('Axel and Blaze take back the city from Mr. X.'), findsNothing);
  });

  testWidgets('a new game starts at the top', (t) async {
    // Short enough for the page to scroll.
    await start(t, size: const Size(1240, 500));
    await send(t, detailsPayload(_sonic));
    await t.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(t.state<ScrollableState>(find.byType(Scrollable)).position.pixels, greaterThan(0));
    await send(t, detailsPayload(_streets));
    expect(find.text('Streets of Rage 2'), findsOneWidget);
    expect(t.state<ScrollableState>(find.byType(Scrollable)).position.pixels, 0);
  });

  GameState task(Game game, GameStatus status, Set<GameAction> actions, {double? progress, bool done = false}) => GameState(
        game: game,
        status: status,
        availableActions: actions,
        showProgressBar: progress != null,
        currentProgress: progress ?? 0,
        hasJustCompleted: done,
      );

  const golden = Game(title: 'Golden Axe (USA).zip', url: 'https://example.com/ga.zip', size: 1024, consoleId: 'md', metadata: GameMetadata(displayTitle: 'Golden Axe'));
  const ecco = Game(title: 'Ecco the Dolphin (USA).zip', url: 'https://example.com/ecco.zip', size: 1024, consoleId: 'md', metadata: GameMetadata(displayTitle: 'Ecco the Dolphin'));

  testWidgets('a tasks payload is the main Task Manager: its tabs, counts and rows', (t) async {
    // No box art: the network image's spinner would keep pumpAndSettle busy.
    final sonic = _sonic.copyWith(details: const GameDetails());
    await start(t);
    await send(
        t,
        tasksPayload([
          task(sonic, GameStatus.downloading, {GameAction.pause, GameAction.cancel}, progress: 0.4),
          task(_streets, GameStatus.downloadQueued, {GameAction.cancel}),
          task(golden, GameStatus.downloadFailed, {GameAction.retryDownload}),
          task(ecco, GameStatus.extracted, {GameAction.none}, done: true),
        ], isFavorite: (id) => id == sonic.gameId));
    expect(find.text('Task Manager'), findsOneWidget);
    // Every close icon is a row's Cancel: no close button, nothing to close to here.
    expect(find.byIcon(Icons.close).evaluate().length, find.byTooltip('Cancel').evaluate().length);
    // The tab buttons and their counts, as on the main screen.
    Finder tab(String label) => find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
    String? count(String label) => t.widgetList<Text>(find.descendant(of: tab(label), matching: find.byType(Text))).map((w) => w.data).where((d) => d != label).firstOrNull;
    expect([for (final l in ['Downloads', 'Extractions', 'Queue', 'Completed', 'Failed']) count(l)], ['2', null, '1', '1', '1']);

    // Downloads: Sonic downloading with its bar and buttons, Streets queued.
    expect(find.text('Sonic The Hedgehog'), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('40.0%'), findsOneWidget);
    expect(find.text('Streets of Rage 2'), findsOneWidget);
    expect(find.text('Dl. Queued'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget, reason: "Sonic's heart");

    await t.tap(find.byTooltip('Pause'));
    await t.tap(find.byTooltip('Remove from favorites'));
    await t.pump();
    expect(requests, [
      {'kind': 'game', 'gameId': sonic.gameId, 'action': 'pause'},
      {'kind': 'favorite', 'gameId': sonic.gameId},
    ]);

    await t.tap(find.text('Failed'));
    await t.pumpAndSettle();
    expect(find.text('Golden Axe'), findsOneWidget);
    expect(find.text('Download Failed'), findsOneWidget);
    await t.tap(find.byTooltip('Retry Download'));
    await t.pump();
    expect(requests.last, {'kind': 'game', 'gameId': golden.gameId, 'action': 'retryDownload'});
  });

  testWidgets('an empty task list shows the empty tabs', (t) async {
    await start(t);
    await send(t, detailsPayload(_sonic));
    await send(t, tasksPayload(const []));
    expect(find.text('No active downloads'), findsOneWidget);
    expect(find.text('Sonic The Hedgehog'), findsNothing);
  });

  testWidgets("details with the game's state show its status and buttons, and a press goes to the main app", (t) async {
    await start(t);
    await send(t, detailsPayload(_sonic, state: task(_sonic, GameStatus.ready, {GameAction.download})));
    expect(find.text('Ready'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
    expect(find.text('Add to favourites'), findsNothing);
    await t.tap(find.text('Download'));
    await t.pump();
    expect(requests, [
      {'kind': 'game', 'gameId': _sonic.gameId, 'action': 'download'}
    ]);

    // The main app sends the new state: the buttons follow.
    await send(t, detailsPayload(_sonic, state: task(_sonic, GameStatus.downloading, {GameAction.pause, GameAction.cancel}, progress: 0.1)));
    expect(find.text('Download'), findsNothing);
    expect(find.text('Downloading'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(requests.last, {'kind': 'game', 'gameId': _sonic.gameId, 'action': 'cancel'});
  });

  testWidgets('a malformed payload keeps the current view', (t) async {
    await start(t);
    await send(t, detailsPayload(_sonic));
    for (final bad in <Object>[
      '{not json',
      '[]',
      {'mode': 'details'},
      {'mode': 'details', 'game': {'title': 'No url'}},
      {'mode': 'tasks', 'tabs': 'none'},
      {'mode': 'tasks', 'tabs': {'downloading': [{'status': 'downloading'}]}},
      {'mode': 'tasks', 'tabs': {'downloading': [{'game': _sonic.toJson(), 'status': 'teleporting'}]}},
      {'mode': 'chess'},
    ]) {
      final reply = await send(t, bad);
      expect(reply, returnsNormally, reason: '$bad');
      expect(t.takeException(), isNull, reason: '$bad');
      expect(find.text('Sonic The Hedgehog'), findsOneWidget, reason: '$bad');
    }
  });
}
