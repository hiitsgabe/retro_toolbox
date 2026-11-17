import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_view.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:photo_view/photo_view.dart';

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

Widget _image(BuildContext context, String url, {BoxFit fit = BoxFit.cover, Alignment alignment = Alignment.center, Widget? placeholder, Widget? fallback}) => SizedBox(key: ValueKey(url));

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

  testWidgets('the catalog\'s release date wins over LaunchBox\'s, which shows before the record loads', (t) async {
    await pump(t, game: _game.copyWith(details: const GameDetails(boxart: _box, launchboxReleaseDate: 19990000)));
    row(t, 'Release date', '1999');
    await pump(t, game: _game.copyWith(details: const GameDetails(boxart: _box, releaseDate: 20000000, launchboxReleaseDate: 19990000)), lb: _lb);
    row(t, 'Release date', '2000');
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

  testWidgets('the logo is drawn at the bottom left of its box from the first frame, with no title while it loads', (t) async {
    final calls = <String, (Alignment, Widget?)>{};
    t.view.physicalSize = const Size(1240, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: GameDetailsView(
          game: _game,
          launchbox: _lb,
          imageBuilder: (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) {
            calls[url] = (alignment, placeholder);
            return SizedBox(key: ValueKey(url));
          },
        ),
      ),
    ));
    final (alignment, placeholder) = calls[_logo.url]!;
    expect(alignment, Alignment.bottomLeft);
    expect(placeholder, isA<SizedBox>()); // not the title
    expect(t.getSize(_url(_logo.url)), const Size(420, 96)); // the whole box: no re-layout when it loads
  });

  testWidgets('while the record loads the logo place is held empty; the title then fills it without moving the buttons', (t) async {
    const matched = Game(
      title: 'Sonic The Hedgehog (USA, Europe).zip',
      url: 'https://example.com/sonic.zip',
      size: 1,
      consoleId: 'md',
      metadata: GameMetadata(displayTitle: 'Sonic The Hedgehog'),
      details: GameDetails(launchboxId: 1, launchboxPlatform: 'Sega Genesis'),
    );
    Future<void> show({required bool pending}) => t.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: GameDetailsView(
              game: matched,
              launchboxPending: pending,
              imageBuilder: _image,
              actions: [FilledButton(onPressed: () {}, child: const Text('Download'))],
            ),
          ),
        ));
    t.view.physicalSize = const Size(1240, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await show(pending: true);
    expect(find.text('Sonic The Hedgehog'), findsNothing);
    final buttonsAt = t.getTopLeft(find.text('Download'));
    await show(pending: false); // found, but no clear logo
    expect(find.text('Sonic The Hedgehog'), findsOneWidget);
    expect(t.getTopLeft(find.text('Download')), buttonsAt);
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
          for (final l in ['Download', 'Add to favourites', 'Select', 'View box art']) FilledButton(onPressed: () {}, child: Text(l))
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

  testWidgets('the d-pad reads a long overview to its end, reaches the back cover and comes back up, every stop on screen', (t) async {
    const longTitle = Game(
      title: 'zelda.zip',
      url: 'https://example.com/zelda.zip',
      size: 1024,
      consoleId: 'snes',
      metadata: GameMetadata(displayTitle: 'The Legend of Zelda: A Link to the Past and Four Swords Anniversary Edition', regions: ['USA']),
      details: GameDetails(boxart: _box),
    );
    final lb = LaunchboxGame(
      id: 1,
      name: 'Zelda',
      overview: List.filled(800, 'lorem').join(' '),
      images: const [_front, _back, _shot1, _shot2, _title],
    );
    // Narrow and short: the cover sits above the text and the hero is taller
    // than the screen.
    const screen = Size(560, 360);
    final nav = GlobalKey<NavigatorState>();
    t.view.physicalSize = screen;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      theme: appTheme(),
      builder: (context, child) => DpadScope(navigatorKey: nav, child: child!),
      home: Scaffold(
        body: GameDetailsView(
          game: longTitle,
          launchbox: lb,
          status: const Text('Ready'),
          onOpenImage: (_) {},
          imageBuilder: (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url), width: 84, height: 120),
          actions: [
            for (final l in ['Download', 'Add to favourites', 'Select', 'View box art'])
              FilledButton(autofocus: l == 'Download', onPressed: () {}, child: Text(l)),
          ],
        ),
      ),
    ));
    await t.pumpAndSettle();
    final position = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    const bar = kToolbarHeight; // no status bar in a test
    final overview = find.text(lb.overview!);
    bool inHero(FocusNode n) => n.context!.findAncestorWidgetOfExactType<FilledButton>() != null;

    // The image each stop holds, read on arrival: the sheet is built lazily.
    final stops = <String?>[];
    void arrived(String step) {
      final node = FocusManager.instance.primaryFocus!;
      String? url;
      void walk(Element e) {
        if (e.widget.key case ValueKey<String>(:final value)) url ??= value;
        e.visitChildElements(walk);
      }

      (node.context! as Element).visitChildElements(walk);
      stops.add(url);
      final r = node.rect;
      expect(r.top, greaterThanOrEqualTo(bar), reason: '$step: $r under the app bar');
      // The overview is taller than the screen: only its top has to show.
      if (r.height < screen.height - bar) expect(r.bottom, lessThanOrEqualTo(screen.height), reason: '$step: $r below the screen');
    }

    arrived('open');
    expect(position.pixels, greaterThan(0), reason: 'the first button sits below the screen at offset 0');
    var backInHero = false;
    for (final key in [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp]) {
      for (var i = 0; i < 80; i++) {
        final (node, pixels) = (FocusManager.instance.primaryFocus!, position.pixels);
        final leaving = overview.evaluate().isNotEmpty ? t.getRect(overview) : null;
        final wasReading = leaving != null && node.rect.overlaps(leaving);
        await t.sendKeyEvent(key);
        await t.pumpAndSettle();
        final now = FocusManager.instance.primaryFocus!;
        if (now == node) {
          if (position.pixels == pixels) break;
          continue;
        }
        // Moving on from the overview only once its far end was in view: no
        // line is scrolled past unread.
        if (wasReading) {
          if (key == LogicalKeyboardKey.arrowDown) {
            expect(leaving.bottom, lessThanOrEqualTo(screen.height), reason: 'left the overview before its end');
          } else {
            expect(leaving.top, greaterThanOrEqualTo(bar), reason: 'left the overview before its start');
          }
        }
        arrived('$key $i');
        if (key == LogicalKeyboardKey.arrowUp && !backInHero && inHero(now)) {
          backInHero = true;
          // Back in the hero: shown from as high up as the button allows.
          expect(now.rect.bottom, greaterThan(screen.height - 20), reason: 'hero not shown from its top: ${now.rect}');
        }
      }
    }
    expect(stops, containsAllInOrder([_shot1.url, _back.url]));
    // And up again through the strip (whichever shot is nearest).
    final shots = {_shot1.url, _shot2.url, _title.url};
    expect(stops.skip(stops.indexOf(_back.url)).where(shots.contains), isNotEmpty);
    expect(backInHero, isTrue);
  });

  testWidgets('the record arriving after focus was placed keeps the focused button on screen', (t) async {
    t.view.physicalSize = const Size(560, 360);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Widget view(LaunchboxGame? lb) => MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: GameDetailsView(
              game: _game,
              launchbox: lb,
              imageBuilder: (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url), width: 84, height: 96),
              actions: [
                for (final l in ['Download', 'Add to favourites', 'Select']) FilledButton(autofocus: l == 'Download', onPressed: () {}, child: Text(l)),
              ],
            ),
          ),
        );
    await t.pumpWidget(view(null));
    await t.pumpAndSettle();
    final download = Focus.of(t.element(find.text('Download')));
    expect(download.hasPrimaryFocus, isTrue);
    expect(download.rect.bottom, lessThanOrEqualTo(360));

    // Logo, summary and rating rows push the buttons down.
    await t.pumpWidget(view(_lb));
    await t.pumpAndSettle();
    expect(download.hasPrimaryFocus, isTrue);
    expect(download.rect.bottom, lessThanOrEqualTo(360));
  });

  testWidgets('contained art decodes by its height, not the page width', (t) async {
    t.view.physicalSize = const Size(2400, 6000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: Scaffold(body: GameDetailsView(game: _game, launchbox: _lb)),
    ));
    CachedNetworkImage net(String url) => t.widget<CachedNetworkImage>(find.byWidgetPredicate((w) => w is CachedNetworkImage && w.imageUrl == url).last);
    expect((net(_back.url).memCacheWidth, net(_back.url).memCacheHeight), (null, 720));
    expect((net(_logo.url).memCacheWidth, net(_logo.url).memCacheHeight), (null, 192));
    expect((net(_front.url).memCacheWidth, net(_front.url).memCacheHeight), (null, 240));
    // Screenshots fill their box: by the box. The last one is the strip's;
    // the hero shows it too, behind the fanart while that loads.
    expect(net(_shot1.url).memCacheWidth, 384);
    t.takeException(); // the image cache has no plugin in tests
  });

  testWidgets('failed art: the background falls to a screenshot, a thumbnail to a placeholder', (t) async {
    t.view.physicalSize = const Size(1240, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: GameDetailsView(
          game: _game,
          launchbox: _lb,
          imageBuilder: (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) =>
              url == _fanart.url || url == _shot2.url ? fallback ?? const SizedBox() : SizedBox(key: ValueKey(url)),
        ),
      ),
    ));
    // In the hero and in the strip.
    expect(_url(_shot1.url), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });

  testWidgets('the zoom viewer decodes at twice the screen, not the scan', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(onPressed: () => showImageViewer(context, _back.url), child: const Text('open'))),
    ));
    await t.tap(find.text('open'));
    await t.pump();
    final provider = t.widget<PhotoView>(find.byType(PhotoView)).imageProvider;
    expect(provider, isA<ResizeImage>());
    provider as ResizeImage;
    expect((provider.width, provider.height, provider.policy), (3840, 2160, ResizeImagePolicy.fit));
    t.takeException(); // the image cache has no plugin in tests
  });
}
