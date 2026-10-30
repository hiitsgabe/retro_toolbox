import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// `find` below is the file lookup helper; widget finders go through `ft`.
import 'package:flutter_test/flutter_test.dart' as ft show find;
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/sports_rom_lookup.dart';
import 'package:retro_toolbox/utils/rom_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every download folder is [dir]; the online library is off unless [library].
class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings(this.dir, {bool library = false}) : super(AppSettings(libraryEnabled: library));
  final String dir;
  @override
  Future<void> get loaded async {}
  @override
  String getDownloadDir(String? consoleId) => dir;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// One PlayStation console in the library.
class _FakeAppState extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeAppState() : super(const AppState(consoles: {'psx': Console(id: 'psx', name: 'PlayStation', urls: [])}));
  @override
  Future<void> get loaded async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Settings and consoles still loading, as on the first screen opened after
/// launch: no download folder and no console until [finish].
class _LateSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _LateSettings() : super(const AppSettings());
  final _done = Completer<void>();
  String _dir = '';
  @override
  Future<void> get loaded => _done.future;
  void finish(String dir) {
    _dir = dir;
    _done.complete();
  }

  @override
  String getDownloadDir(String? consoleId) => _dir;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _LateAppState extends StateNotifier<AppState> implements AppStateNotifier {
  _LateAppState() : super(const AppState());
  final _done = Completer<void>();
  @override
  Future<void> get loaded => _done.future;
  void finish() {
    state = const AppState(consoles: {'psx': Console(id: 'psx', name: 'PlayStation', urls: [])});
    _done.complete();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDownloads extends StateNotifier<DownloadState> implements DownloadNotifier {
  _FakeDownloads() : super(const DownloadState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Every console's catalog is [games].
class _FakeCatalog extends Fake implements CatalogService {
  _FakeCatalog(this.games);
  final List<Game> games;
  @override
  Future<List<Game>> loadCatalog(String consoleId,
          {String? iaAccessKey,
          String? iaSecretKey,
          String? authToken,
          void Function(int done, int total)? onProgress,
          void Function(String status)? onStatus}) async =>
      games;
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('rom_lookup_'));
  tearDown(() => root.deleteSync(recursive: true));

  File touch(String relative) => File(p.join(root.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  Future<String?> find(String gameId, [List<String>? dirs]) =>
      SportsRomLookup.findLocal(dirs: dirs ?? [root.path], gameId: gameId);

  group('findLocal', () {
    test('finds Winning Eleven as a loose .bin', () async {
      touch('Winning Eleven 2002 (Japan).bin');
      expect(p.basename((await find('we2002'))!), 'Winning Eleven 2002 (Japan).bin');
    });

    test('prefers the .cue over its .bin, and over the archive it came from', () async {
      touch('World Soccer Jikkyou Winning Eleven 2002 (Japan).zip');
      touch('World Soccer Jikkyou Winning Eleven 2002 (Japan).bin');
      touch('World Soccer Jikkyou Winning Eleven 2002 (Japan).cue');
      expect(p.extension((await find('we2002'))!), '.cue');
    });

    test('finds a file inside a folder named after the game', () async {
      touch('World Soccer Winning Eleven 2002 (Japan)/Track 01.bin');
      expect(p.basename((await find('we2002'))!), 'Track 01.bin');
    });

    test('skips extra tracks when the first one is there', () async {
      touch('Winning Eleven 2002 (Japan) (Track 2).bin');
      touch('Winning Eleven 2002 (Japan) (Track 1).bin');
      expect(p.basename((await find('we2002'))!), 'Winning Eleven 2002 (Japan) (Track 1).bin');
    });

    test('matches a name written without spaces', () async {
      touch('PES2013.iso');
      expect(p.basename((await find('pes2013-ps2'))!), 'PES2013.iso');
    });

    test('finds PES 2013 under its long title', () async {
      touch('PES 2013 - Pro Evolution Soccer (USA) (En,Fr,Es,Pt).iso');
      expect(await find('pes2013-ps2'), isNotNull);
    });

    test('ignores extensions the patcher cannot take', () async {
      touch('NHL 07 (USA).cso');
      touch('Winning Eleven 2002 (Japan).txt');
      expect(await find('nhl07-psp'), isNull);
      expect(await find('we2002'), isNull);
    });

    test('ignores other games and missing folders', () async {
      touch('Gran Turismo 3 (USA).iso');
      expect(await find('pes2013-ps2', [root.path, p.join(root.path, 'missing')]), isNull);
    });

    test('prefers the preferred region among equal matches', () async {
      touch('NHL 07 (Europe).iso');
      touch('NHL 07 (USA).iso');
      expect(p.basename((await find('nhl07-psp'))!), 'NHL 07 (USA).iso');
    });

    test('picks the data track when tracks are numbered with two digits', () async {
      touch('Winning Eleven 2002 (Japan) (Track 02).bin');
      touch('Winning Eleven 2002 (Japan) (Track 01).bin');
      touch('Winning Eleven 2002 (Japan) (Track 10).bin');
      expect(p.basename((await find('we2002'))!), 'Winning Eleven 2002 (Japan) (Track 01).bin');
    });

    test('picks the data track among bare track names in a game folder', () async {
      touch('Winning Eleven 2002 (Japan)/Track 03.bin');
      touch('Winning Eleven 2002 (Japan)/Track 02.bin');
      touch('Winning Eleven 2002 (Japan)/Track 01.bin');
      expect(p.basename((await find('we2002'))!), 'Track 01.bin');
    });

    group('in the general download folder', () {
      // root is the general folder; each console keeps its own folder inside.
      String dir(String name) => p.join(root.path, name);
      Future<String?> findPsp() => SportsRomLookup.findLocal(
          dirs: [dir('psp')], looseDirs: [root.path], gameId: 'nhl07-psp', skip: [dir('psp'), dir('ps2')]);

      test("does not offer another console's copy of the game", () async {
        touch('ps2/NHL 07 (USA).iso');
        expect(await findPsp(), isNull);
        touch('psp/NHL 07 (Europe).iso');
        expect(p.relative((await findPsp())!, from: root.path), p.join('psp', 'NHL 07 (Europe).iso'));
      });

      test('still finds loose files and extracted game folders there', () async {
        touch('NHL 07 (USA)/NHL 07 (USA).iso');
        expect(p.basename((await findPsp())!), 'NHL 07 (USA).iso');
      });

      test("ranks the console's own folder ahead of it", () async {
        touch('NHL 07 (USA).iso');
        touch('psp/NHL 07 (Europe).iso');
        expect(p.relative((await findPsp())!, from: root.path), p.join('psp', 'NHL 07 (Europe).iso'));
      });

      test("ranks the console's own folder ahead even of a closer name there", () async {
        touch('NHL 07 (USA).iso'); // maybe the PS2 disc, dropped loose
        touch('psp/NHL07.iso');
        expect(p.relative((await findPsp())!, from: root.path), p.join('psp', 'NHL07.iso'));
      });

      test("does not go into another system's folder it does not know", () async {
        touch('ps2 (old)/NHL 07 (USA).iso');
        touch('megadrive/NHL 07.zip');
        expect(await findPsp(), isNull);
      });
    });
  });

  group('extractedFor', () {
    test('finds the image next to the downloaded archive', () {
      touch('Winning Eleven 2002 (Japan).zip');
      touch('Winning Eleven 2002 (Japan).cue');
      final found = SportsRomLookup.extractedFor(
          dir: root.path, archiveName: 'Winning Eleven 2002 (Japan).zip', gameId: 'we2002');
      expect(p.extension(found!), '.cue');
    });

    test('finds the image in the folder the archive was extracted to', () {
      touch('Pro Evolution Soccer 2013 (USA)/Pro Evolution Soccer 2013 (USA).iso');
      final found = SportsRomLookup.extractedFor(
          dir: root.path, archiveName: 'Pro Evolution Soccer 2013 (USA).zip', gameId: 'pes2013-ps2');
      expect(p.basename(found!), 'Pro Evolution Soccer 2013 (USA).iso');
    });

    test('finds the CHD the conversion left next to the archive', () {
      touch('Alpha Title.chd');
      final found = SportsRomLookup.extractedFor(dir: root.path, archiveName: 'Alpha Title.zip', gameId: 'we2002');
      expect(p.extension(found!), '.chd');
    });

    test('picks the data track among bare track names', () {
      touch('Winning Eleven 2002 (Japan)/Track 02.bin');
      touch('Winning Eleven 2002 (Japan)/Track 01.bin');
      expect(p.basename(SportsRomLookup.extractedFor(dir: root.path, archiveName: 'Winning Eleven 2002 (Japan).zip', gameId: 'we2002')!), 'Track 01.bin');
    });

    test('is null when nothing was extracted', () {
      touch('NHL 07 (USA).zip');
      expect(SportsRomLookup.extractedFor(dir: root.path, archiveName: 'NHL 07 (USA).zip', gameId: 'nhl07-psp'),
          isNull);
    });
  });

  test('a title without spaces still scores as a match', () {
    expect(romFuzzyScore('pes 2013', 'PES2013.iso'), greaterThanOrEqualTo(kRomMatchThreshold));
    expect(romFuzzyScore('Winning Eleven 2002', 'WinningEleven2002.bin'), greaterThanOrEqualTo(kRomMatchThreshold));
  });

  group('romPickProblem', () {
    File zip(String name, List<String> entries) {
      final a = Archive();
      for (final e in entries) {
        a.addFile(ArchiveFile(e, 4, [1, 2, 3, 4]));
      }
      final f = File(p.join(root.path, name))..createSync(recursive: true);
      f.writeAsBytesSync(ZipEncoder().encode(a));
      return f;
    }

    test('takes any file name with a good extension', () async {
      final rom = touch('Whatever name you like.bin');
      expect(await romPickProblem(rom.path, 'we2002'), isNull);
    });

    test('refuses a wrong extension, naming the taken ones', () async {
      final txt = touch('Winning Eleven 2002 (Japan).txt');
      final problem = await romPickProblem(txt.path, 'we2002');
      expect(problem, contains('Not a Winning Eleven 2002'));
      expect(problem, contains('.cue'));
    });

    test('looks inside a zip for a file of the game type', () async {
      expect(await romPickProblem(zip('we.zip', ['readme.txt', 'game.bin']).path, 'we2002'), isNull);
      final problem = await romPickProblem(zip('no-rom.zip', ['readme.txt']).path, 'we2002');
      expect(problem, contains('zip holds no'));
      expect(problem, contains('.bin'));
    });

    test('takes a CHD disc image for every disc game', () async {
      for (final id in ['we2002', 'nhl05-ps2', 'pes2013-ps2', 'nhl07-psp', 'mvp-psp']) {
        expect(await romPickProblem(touch('Game $id.chd').path, id), isNull, reason: id);
      }
    });

    test('a game whose zips hold nothing (NHL 07 takes .iso only) still passes a plain .iso', () async {
      final iso = touch('NHL 07 (USA).iso');
      expect(await romPickProblem(iso.path, 'nhl07-psp'), isNull);
    });
  });

  group('the wizard ROM step', () {
    const info = PatcherInfo(gameId: 'we2002', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn']);
    const skeleton = ValueKey('rom-lookup-skeleton');

    // The app state the wizard reads its consoles from loads preferences.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // [catalog]: the online library is on, with one PlayStation console whose
    // catalog holds these games.
    Future<void> pump(WidgetTester t, {List<Game>? catalog}) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1200, 900);
      addTearDown(t.view.reset);
      if (catalog != null) {
        SportsRomLookup.catalogService = () => _FakeCatalog(catalog);
        addTearDown(() => SportsRomLookup.catalogService = CatalogService.new);
      }
      await t.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => _FakeSettings(root.path, library: catalog != null)),
          if (catalog != null) ...[
            appStateProvider.overrideWith((_) => _FakeAppState()),
            downloadProvider.overrideWith((_) => _FakeDownloads()),
          ],
        ],
        child: const MaterialApp(home: SportPatcherWizardScreen(info: info, initialLeagues: [])),
      ));
    }

    bool focused(WidgetTester t, String text) => Focus.of(t.element(ft.find.text(text))).hasPrimaryFocus;

    // The device lookup runs on another isolate: let real time pass until
    // its placeholder goes.
    Future<void> settleLookup(WidgetTester t) async {
      for (var i = 0; i < 100 && ft.find.byKey(skeleton).evaluate().isNotEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump();
      }
    }

    testWidgets('holds a placeholder while it looks, then puts the file found first', (t) async {
      touch('Winning Eleven 2002 (Japan).bin');
      await pump(t);
      expect(ft.find.byKey(skeleton), findsOneWidget);
      expect(ft.find.text('Looking for Winning Eleven 2002…'), findsOneWidget);

      await settleLookup(t);
      expect(ft.find.byKey(skeleton), findsNothing);
      expect(ft.find.byKey(const ValueKey('rom-local-card')), findsOneWidget);
      // The found file's button is the step's first control, above the picker
      // and the expectation note, and has focus: A uses it at once.
      final use = t.getTopLeft(ft.find.text('Use this file')).dy;
      expect(use, lessThan(t.getTopLeft(ft.find.text('Pick a file instead')).dy));
      expect(use, lessThan(t.getTopLeft(ft.find.byIcon(Icons.info_outline)).dy));
      expect(focused(t, 'Use this file'), isTrue);

      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      // Using the found file moves straight on: the ROM step is done.
      expect(ft.find.text('Select ROM'), findsNothing);
      expect(ft.find.byKey(const ValueKey('rom-local-card')), findsNothing);
    });

    testWidgets('first open after launch: the placeholder waits for settings and consoles, then the file shows', (t) async {
      touch('Winning Eleven 2002 (Japan).bin');
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1200, 900);
      addTearDown(t.view.reset);
      final settings = _LateSettings();
      final app = _LateAppState();
      await t.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => settings),
          appStateProvider.overrideWith((_) => app),
        ],
        child: const MaterialApp(home: SportPatcherWizardScreen(info: info, initialLeagues: [])),
      ));
      expect(ft.find.byKey(skeleton), findsOneWidget);
      // Still loading: the placeholder stays rather than a lookup of nowhere.
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      expect(ft.find.byKey(skeleton), findsOneWidget);

      settings.finish(root.path);
      app.finish();
      await t.pump();
      await settleLookup(t);
      expect(ft.find.byKey(const ValueKey('rom-local-card')), findsOneWidget);
    });

    testWidgets('a file found late takes no focus from the picker', (t) async {
      touch('Winning Eleven 2002 (Japan).bin');
      await pump(t);
      Focus.of(t.element(ft.find.text('Choose'))).requestFocus();
      await t.pump();

      await settleLookup(t);
      expect(ft.find.byKey(const ValueKey('rom-local-card')), findsOneWidget);
      expect(focused(t, 'Pick a file instead'), isTrue);
      expect(focused(t, 'Use this file'), isFalse);
    });

    testWidgets('with nothing found the placeholder goes and the file picker keeps focus', (t) async {
      // The library is on too, with no match: both lookups must end.
      await pump(t, catalog: [const Game(title: 'Gran Turismo (USA)', url: 'https://x/Gran Turismo (USA).zip', size: 1, consoleId: 'psx')]);
      expect(ft.find.byKey(skeleton), findsOneWidget);
      Focus.of(t.element(ft.find.text('Choose'))).requestFocus();
      await t.pump();

      await settleLookup(t);
      expect(ft.find.byKey(skeleton), findsNothing);
      expect(ft.find.byKey(const ValueKey('rom-local-card')), findsNothing);
      expect(ft.find.byKey(const ValueKey('rom-catalog-card')), findsNothing);
      expect(focused(t, 'Choose'), isTrue);
    });

    testWidgets('a library match comes first, its download focused', (t) async {
      await pump(t, catalog: [
        const Game(title: 'Winning Eleven 2002 (Japan)', url: 'https://x/Winning Eleven 2002 (Japan).zip', size: 500000000, consoleId: 'psx'),
      ]);
      expect(ft.find.text('Looking for Winning Eleven 2002…'), findsOneWidget);

      await settleLookup(t);
      expect(ft.find.byKey(const ValueKey('rom-catalog-card')), findsOneWidget);
      final download = t.getTopLeft(ft.find.text('Download (500 MB)')).dy;
      expect(download, lessThan(t.getTopLeft(ft.find.text('Pick a file instead')).dy));
      expect(focused(t, 'Download (500 MB)'), isTrue);
    });

    testWidgets('using the downloaded file goes straight to the next step', (t) async {
      touch('Winning Eleven 2002 (Japan).zip');
      await pump(t, catalog: [
        const Game(title: 'Winning Eleven 2002 (Japan)', url: 'https://x/Winning Eleven 2002 (Japan).zip', size: 500000000, consoleId: 'psx'),
      ]);
      await settleLookup(t);
      expect(ft.find.byKey(const ValueKey('rom-catalog-card')), findsOneWidget);

      await t.tap(ft.find.text('Use downloaded file'));
      await t.pumpAndSettle();
      // Off the ROM step at once: the rosters step is showing.
      expect(ft.find.text('Use downloaded file'), findsNothing);
      expect(ft.find.text('Pick your options, then Next downloads the league data.'), findsOneWidget);
    });

    testWidgets('a download queued before shows as in progress, with no second Download', (t) async {
      // Queued from the wizard, then the wizard was left and reopened: the
      // task list has the row, and the downloader has not started it yet
      // (other downloads first), so the file and the progress are both absent.
      const game = Game(title: 'Winning Eleven 2002 (Japan)', url: 'https://x/Winning Eleven 2002 (Japan).zip', size: 500000000, consoleId: 'psx');
      await pump(t, catalog: [game]);
      ProviderScope.containerOf(t.element(ft.find.byType(SportPatcherWizardScreen))).read(gameStateManagerProvider.notifier)
        ..registerTransientGame(game)
        ..updateQueueState(game.gameId, TaskType.download);
      await settleLookup(t);
      expect(ft.find.byKey(const ValueKey('rom-catalog-card')), findsOneWidget);
      expect(ft.find.text('Starting download…'), findsOneWidget);
      expect(ft.find.text('Download (500 MB)'), findsNothing);
    });
  });
}
