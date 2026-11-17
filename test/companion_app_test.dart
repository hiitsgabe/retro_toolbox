import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/companion/companion_app.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
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

Widget _image(BuildContext context, String url, {BoxFit fit = BoxFit.cover, Widget? fallback}) => SizedBox(key: ValueKey(url));

void main() {
  late List<String> sent;

  setUp(() {
    sent = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      sent.add(call.method);
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

  Map<String, dynamic> row(String title, String status, double? progress, String state) =>
      {'title': title, 'status': status, 'progress': progress, 'state': state};

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

  testWidgets('before any payload it shows the empty task list', (t) async {
    await start(t);
    expect(find.text('No tasks running'), findsOneWidget);
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
    expect(find.text('No tasks running'), findsNothing);
    expect(find.text('About'), findsNothing);
    expect(asked, isEmpty, reason: 'no LaunchBox id, nothing to look up');
    noActions();
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

  testWidgets('a tasks payload shows its rows, with a bar only where there is progress', (t) async {
    await start(t);
    await send(t, {
      'mode': 'tasks',
      'tasks': [
        row('Sonic The Hedgehog', 'Downloading 40%', 0.4, 'active'),
        row('Streets of Rage 2', 'Queued', null, 'queued'),
        row('Golden Axe', 'Download failed', null, 'failed'),
        row('Ecco the Dolphin', 'Ready', null, 'done'),
      ],
    });
    expect(find.text('Tasks'), findsOneWidget);
    for (final s in ['Sonic The Hedgehog', 'Downloading 40%', 'Streets of Rage 2', 'Queued', 'Golden Axe', 'Download failed', 'Ecco the Dolphin', 'Ready']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(find.text('No tasks running'), findsNothing);
    final bar = find.byType(LinearProgressIndicator);
    expect(bar, findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(bar).value, 0.4);
    // The bar is Sonic's: it sits between its row's title and the next row.
    final y = t.getCenter(bar).dy;
    expect(y, greaterThan(t.getCenter(find.text('Sonic The Hedgehog')).dy));
    expect(y, lessThan(t.getCenter(find.text('Streets of Rage 2')).dy));

    final error = Theme.of(t.element(find.text('Golden Axe'))).colorScheme.error;
    expect(t.widget<Text>(find.text('Download failed')).style?.color, error);
    expect(
      find.ancestor(of: find.text('Ecco the Dolphin'), matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1)),
      findsOneWidget,
      reason: 'done is dimmed',
    );
    noActions();
  });

  testWidgets('an empty task list says no tasks are running', (t) async {
    await start(t);
    await send(t, detailsPayload(_sonic));
    await send(t, {'mode': 'tasks', 'tasks': <Object>[]});
    expect(find.text('No tasks running'), findsOneWidget);
    expect(find.text('Sonic The Hedgehog'), findsNothing);
  });

  testWidgets('a malformed payload keeps the current view', (t) async {
    await start(t);
    await send(t, detailsPayload(_sonic));
    for (final bad in <Object>[
      '{not json',
      '[]',
      {'mode': 'details'},
      {'mode': 'details', 'game': {'title': 'No url'}},
      {'mode': 'tasks', 'tasks': 'none'},
      {'mode': 'tasks', 'tasks': [{'status': 'no title'}]},
      {'mode': 'chess'},
    ]) {
      final reply = await send(t, bad);
      expect(reply, returnsNormally, reason: '$bad');
      expect(t.takeException(), isNull, reason: '$bad');
      expect(find.text('Sonic The Hedgehog'), findsOneWidget, reason: '$bad');
    }
  });
}
