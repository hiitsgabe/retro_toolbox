import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_view.dart';

const _box = 'https://thumbnails.libretro.com/sonic.png';

const _game = Game(
  title: 'Sonic The Hedgehog (USA, Europe).zip',
  url: 'https://example.com/sonic.zip',
  size: 3 * 1024 * 1024,
  consoleId: 'md',
  metadata: GameMetadata(displayTitle: 'Sonic The Hedgehog', regions: ['USA']),
  details: GameDetails(boxart: _box),
);

const _logo = LaunchboxImage(LaunchboxImageType.clearLogo, 'logo.png', 'North America');
const _front = LaunchboxImage(LaunchboxImageType.boxFront, 'front.jpg', 'North America');
const _back = LaunchboxImage(LaunchboxImageType.boxBack, 'back.jpg', 'North America');
const _fanart = LaunchboxImage(LaunchboxImageType.fanart, 'fanart.jpg');
const _shot1 = LaunchboxImage(LaunchboxImageType.screenshot, 'shot1.jpg');
const _shot2 = LaunchboxImage(LaunchboxImageType.screenshot, 'shot2.jpg');
const _title = LaunchboxImage(LaunchboxImageType.titleScreen, 'title.jpg');

const _lb = LaunchboxGame(
  id: 1,
  name: 'Sonic the Hedgehog',
  releaseDate: 19910623,
  overview: 'Sonic races through Green Hill Zone to stop Dr. Robotnik.',
  maxPlayers: 2,
  rating: 4.2,
  ratingCount: 120,
  genres: ['Platform', 'Action'],
  developer: 'Sonic Team',
  publisher: 'Sega',
  esrb: 'E - Everyone',
  // The title screen comes first in the file; the strip still shows gameplay first.
  images: [_title, _logo, _front, _back, _fanart, _shot1, _shot2],
);

Widget _image(BuildContext context, String url, {BoxFit fit = BoxFit.cover, Widget? fallback}) => SizedBox(key: ValueKey(url));

Finder _url(String url) => find.byKey(ValueKey(url));

void main() {
  Future<void> pump(
    WidgetTester t, {
    LaunchboxGame? lb,
    Game game = _game,
    List<Widget>? actions,
    ValueChanged<String>? onOpenImage,
    Size size = const Size(1240, 3000),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: GameDetailsView(game: game, launchbox: lb, actions: actions, onOpenImage: onOpenImage, imageBuilder: _image),
      ),
    ));
  }

  void row(WidgetTester t, String label, String value) {
    Finder cell(String text) => find.descendant(of: find.byType(Table), matching: find.text(text));
    expect(cell(label), findsOneWidget, reason: label);
    expect(cell(value), findsOneWidget, reason: '$label: $value');
    expect(t.getCenter(cell(label)).dy, closeTo(t.getCenter(cell(value)).dy, 1), reason: '$label and $value share a row');
  }

  testWidgets('with LaunchBox data: logo, summary line, rating, details, screenshots, overview, back cover', (t) async {
    await pump(t, lb: _lb);

    expect(_url(_logo.url), findsOneWidget);
    expect(find.text('Sonic The Hedgehog'), findsNothing);
    expect(find.text('1991 · Sega · Platform'), findsOneWidget);
    expect(find.text('4.2 (120 votes)'), findsOneWidget);
    // Hero background is the fanart, the cover the LaunchBox front.
    expect(_url(_fanart.url), findsOneWidget);
    expect(_url(_front.url), findsOneWidget);

    row(t, 'Developer', 'Sonic Team');
    row(t, 'Publisher', 'Sega');
    row(t, 'Release date', '1991-06-23');
    row(t, 'Players', '1-2 players');
    row(t, 'Co-op', 'No');
    row(t, 'ESRB', 'E - Everyone');
    row(t, 'Region', 'USA');
    row(t, 'Size', formatBytes(_game.size));
    row(t, 'Genres', 'Platform, Action');

    expect(find.text('Screenshots'), findsOneWidget);
    final xs = [
      for (final i in [_shot1, _shot2, _title]) t.getTopLeft(_url(i.url)).dx
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(xs.toSet(), hasLength(3));

    expect(find.text('About'), findsOneWidget);
    expect(find.text(_lb.overview!), findsOneWidget);
    expect(find.text('Back of the box'), findsOneWidget);
    expect(_url(_back.url), findsOneWidget);
  });

  testWidgets('a year-only date shows the year; co-op shows in the players', (t) async {
    await pump(t, lb: const LaunchboxGame(id: 2, name: 'G', releaseDate: 19990000, maxPlayers: 4, cooperative: true));
    row(t, 'Release date', '1999');
    row(t, 'Co-op', 'Yes');
    expect(find.text('1-4 players · Co-op'), findsOneWidget);
  });

  testWidgets('without LaunchBox data: the title, no rating, no screenshots or about, the size, blurred box art', (t) async {
    await pump(t);

    expect(find.text('Sonic The Hedgehog'), findsOneWidget);
    expect(find.textContaining('votes'), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
    expect(find.text('Screenshots'), findsNothing);
    expect(find.text('About'), findsNothing);
    expect(find.text('Back of the box'), findsNothing);
    row(t, 'Size', formatBytes(_game.size));
    row(t, 'Region', 'USA');
    expect(find.descendant(of: find.byType(Table), matching: find.text('Developer')), findsNothing);

    expect(find.ancestor(of: _url(_box), matching: find.byType(ImageFiltered)), findsOneWidget);
    // The cover is the same box art, sharp.
    expect(_url(_box), findsNWidgets(2));
  });

  testWidgets('no background at all leaves no image', (t) async {
    await pump(t, game: const Game(title: 'Bare', url: 'https://example.com/bare.zip', size: 0, consoleId: 'md'));
    expect(find.text('Bare'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.descendant(of: find.byType(Table), matching: find.text('Size')), findsNothing);
  });

  testWidgets('actions null renders no buttons; given, they render', (t) async {
    await pump(t, lb: _lb);
    expect(find.byWidgetPredicate((w) => w is ButtonStyleButton), findsNothing);

    await pump(t, lb: _lb, actions: [FilledButton(onPressed: () {}, child: const Text('Download'))]);
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
  });

  testWidgets('wide: the cover sits right of the text; under 600 px it moves above it', (t) async {
    await pump(t, lb: _lb, size: const Size(1920, 1080));
    expect(t.takeException(), isNull);
    expect(t.getTopLeft(_url(_front.url)).dx, greaterThan(t.getTopRight(_url(_logo.url)).dx));

    await pump(t, lb: _lb, size: const Size(400, 800));
    expect(t.takeException(), isNull);
    expect(t.getBottomLeft(_url(_front.url)).dy, lessThanOrEqualTo(t.getTopLeft(_url(_logo.url)).dy));
  });

  testWidgets('at 400 px wide it lays out without overflow, scrolled to the end too', (t) async {
    await pump(t,
        lb: _lb,
        actions: [
          for (final l in ['Download', 'Add to favourites', 'Select', 'View box art', 'Filters']) FilledButton(onPressed: () {}, child: Text(l))
        ],
        size: const Size(400, 800));
    expect(t.takeException(), isNull);
    await t.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(_url(_back.url), findsOneWidget);
  });

  testWidgets('d-pad: down from the actions reaches the screenshots; back up shows the whole hero', (t) async {
    final opened = <String>[];
    await pump(
      t,
      lb: _lb,
      size: const Size(1240, 1080),
      onOpenImage: opened.add,
      actions: [FilledButton(autofocus: true, onPressed: () {}, child: const Text('Download'))],
    );
    await t.pump();
    final position = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    Focus.of(t.element(find.text('Download'))).focusInDirection(TraversalDirection.down);
    await t.pumpAndSettle();
    final shot = Focus.of(t.element(_url(_shot1.url)));
    expect(shot.hasPrimaryFocus, isTrue);
    expect(position.pixels, greaterThan(0));

    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, [_shot1.url]);

    shot.focusInDirection(TraversalDirection.up);
    await t.pumpAndSettle();
    expect(Focus.of(t.element(find.text('Download'))).hasPrimaryFocus, isTrue);
    expect(position.pixels, 0);
  });
}
