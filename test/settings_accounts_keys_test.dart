import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/services/catalog_logins.dart';
import 'package:retro_toolbox/services/key_files.dart';
import 'package:retro_toolbox/services/storage_usage.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/settings/console_auth_setting.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeLaunchbox extends StateNotifier<LaunchboxState> implements LaunchboxNotifier {
  _FakeLaunchbox() : super(const LaunchboxState(loading: false));
  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDualScreen extends StateNotifier<DualScreenState> implements DualScreenNotifier {
  _FakeDualScreen() : super(const DualScreenState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSync extends SaveSyncNotifier {
  _FakeSync(SaveSyncState s) {
    state = s;
  }
  final calls = <String>[];
  @override
  Future<void> loadHub() async => calls.add('loadHub');
  @override
  Future<void> signOut() async => calls.add('signOut');
  @override
  Future<void> signInWithGoogle() async => calls.add('signIn');
  @override
  Future<String?> catalogSetting() async => null;
}

// Fixtures in the shape of a catalog with a cookie login shared by two
// consoles (here the user's real site), one console with its own token, and
// consoles on archive.org. Nothing in lib/ names any of these.
Map<String, dynamic> _cookieLogin(String host, String message) => {
      'cookies': true,
      'auth_message': message,
      'signin': {'url': 'https://$host/api/login', 'register_url': 'https://$host/register', 'params': ['username', 'password'], 'token_regex': 't=(.*)'},
    };

final _switch = Console(id: 'switch', name: 'Nintendo Switch', urls: const ['https://files.example/switch'], auth: _cookieLogin('not.ultranx.ru', 'Sign in with your site account'));
final _switch2 = Console(id: 'switch2', name: 'Switch Updates', urls: const ['https://files.example/updates'], auth: _cookieLogin('not.ultranx.ru', 'Updates need the same login'));
const _vault = Console(id: 'vault', name: 'Vault', urls: ['https://vault.example/'], auth: {'token': ''});
const _psx = Console(id: 'psx', name: 'PlayStation', urls: ['https://archive.org/download/psx-set']);
const _snes = Console(id: 'snes', name: 'Super Nintendo', urls: ['https://archive.org/download/snes-set']);
const _plain = Console(id: 'md', name: 'Mega Drive', urls: ['https://files.example/md']);

void main() {
  group('catalogLogins', () {
    test('consoles with the same sign-in site share one login, titled by its host', () {
      final logins = catalogLogins([_psx, _switch, _vault, _switch2, _plain]);
      expect(logins.map((l) => l.title), ['not.ultranx.ru', 'Vault']);
      expect(logins.first.consoleIds, ['switch', 'switch2']);
      expect(logins.last.consoleIds, ['vault']);
    });

    test('without a sign-in page, the same auth message groups them; else one each', () {
      const a = Console(id: 'a', name: 'A', urls: [], auth: {'auth_message': 'Paste your key from the members page'});
      const b = Console(id: 'b', name: 'B', urls: [], auth: {'auth_message': 'Paste your key from the members page'});
      const c = Console(id: 'c', name: 'C', urls: [], auth: {'token': 'x'});
      const d = Console(id: 'd', name: 'D', urls: [], auth: {'token': 'y'});
      final logins = catalogLogins([a, b, c, d]);
      expect(logins.map((l) => l.consoleIds), [
        ['a', 'b'],
        ['c'],
        ['d'],
      ]);
      expect(logins.first.title, 'A');
    });

    test('Internet Archive consoles are the archive.org ones', () {
      expect(internetArchiveConsoles([_psx, _switch, _snes, _plain]).map((c) => c.id), ['psx', 'snes']);
    });
  });

  testWidgets('a settings row draws its own focus outline; the global one skips it', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      builder: (context, child) => DpadScope(navigatorKey: nav, child: child!),
      home: Scaffold(
        body: Column(children: [
          SettingsTile(onTap: () {}, child: const Text('row')),
          TextButton(onPressed: () {}, child: const Text('button')),
        ]),
      ),
    ));
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final outline = t.renderObject(find.byKey(const ValueKey('dpad-focus-outline')));

    Focus.of(t.element(find.text('button'))).requestFocus();
    await t.pumpAndSettle();
    expect(outline, paints..rrect());

    Focus.of(t.element(find.text('row'))).requestFocus();
    await t.pumpAndSettle();
    expect(outline, paintsNothing);
    final tile = t.widget<Material>(find.descendant(of: find.byType(SettingsTile), matching: find.byType(Material)).first);
    expect((tile.shape as RoundedRectangleBorder).side.width, 2, reason: 'its own outline instead');
  });

  group('storage', () {
    test('measures the game lists, box art listings, LaunchBox and sports data', () {
      final tmp = Directory.systemTemp.createTempSync('rt_storage');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final cache = Directory(p.join(tmp.path, 'cache'))..createSync();
      final support = Directory(p.join(tmp.path, 'support'))..createSync();
      File(p.join(cache.path, 'catalog_v2_psx.json')).writeAsBytesSync(List.filled(1000, 1));
      File(p.join(cache.path, 'boxarts_ab12.json')).writeAsBytesSync(List.filled(200, 1));
      File(p.join(cache.path, 'other.json')).writeAsBytesSync(List.filled(5000, 1));
      Directory(p.join(support.path, 'launchbox')).createSync();
      File(p.join(support.path, 'launchbox', 'snes.json.gz')).writeAsBytesSync(List.filled(300, 1));
      File(p.join(support.path, 'sports_formations.json')).writeAsBytesSync(List.filled(40, 1));
      Directory(p.join(support.path, 'rrp_cache', 'x')).createSync(recursive: true);
      File(p.join(support.path, 'rrp_cache', 'x', 'roster.json')).writeAsBytesSync(List.filled(60, 1));

      final u = measureStorage(cacheDir: cache.path, supportDir: support.path, consoleFiles: {'psx': 'catalog_v2_psx.json', 'md': 'catalog_v2_md.json'});
      expect(u.catalog, 1200);
      expect(u.launchbox, 300);
      expect(u.sports, 100);
      expect(u.consoles, {'psx': 1000, 'md': 0});
      expect(u.total, 1600);
    });

    test('sizes read as KB under a megabyte, MB above', () {
      expect(storageSize(640 * 1024), '640 KB');
      expect(storageSize((2.5 * 1024 * 1024).round()), '2.5 MB');
      expect(storageSize(18 * 1024 * 1024), '18 MB');
    });
  });

  group('screen', () {
    final nav = GlobalKey<NavigatorState>();
    late _FakeApp app;
    late _FakeSync sync;

    void saved(Map<String, dynamic> extra) => SharedPreferences.setMockInitialValues({
          'app_settings': jsonEncode({
            'libraryEnabled': true,
            'generalSettings': {'downloadDir': '/roms'},
            ...extra,
          }),
        });

    Future<ProviderContainer> pump(
      WidgetTester t, {
      required Map<String, Console> consoles,
      SettingsSection? section,
      Size size = const Size(1280, 900),
      bool google = true,
      SaveSyncState syncState = const SaveSyncState(hubKind: HubKind.drive, googleEmail: 'me@example.com', googleAvailable: true),
    }) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      app = _FakeApp(AppState(consoles: consoles));
      sync = _FakeSync(syncState);
      final c = ProviderContainer(overrides: [
        appStateProvider.overrideWith((ref) => app),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
        launchboxProvider.overrideWith((ref) => _FakeLaunchbox()),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        dualScreenProvider.overrideWith((ref) => _FakeDualScreen()),
        saveSyncAvailableProvider.overrideWith((ref) => google),
        saveSyncProvider.overrideWith((ref) => sync),
        storageUsageProvider.overrideWith((ref) async => const StorageUsage(catalog: 0, launchbox: 0, sports: 0)),
      ]);
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          navigatorKey: nav,
          builder: (context, child) => DpadScope(navigatorKey: nav, child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(section: section))),
                child: const Text('open settings'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open settings'));
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('Accounts lists Internet Archive, each catalog login once, and Google', (t) async {
      saved({'iaAccessKey': 'a', 'iaSecretKey': 'b'});
      await pump(t, consoles: {'psx': _psx, 'switch': _switch, 'switch2': _switch2, 'snes': _snes}, section: SettingsSection.accounts);
      expect(find.text('Internet Archive'), findsOneWidget);
      expect(find.text('Used by 2 consoles. Connected'), findsOneWidget);
      expect(find.text('not.ultranx.ru'), findsOneWidget);
      expect(find.text('Nintendo Switch, Switch Updates. Not signed in'), findsOneWidget);
      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Keeps saves in sync between devices. Signed in as me@example.com'), findsOneWidget);
      // Order: catalog logins, then Save Sync.
      expect(t.getTopLeft(find.text('not.ultranx.ru')).dy, lessThan(t.getTopLeft(find.text('Google Drive')).dy));
      expect(sync.calls, isNot(contains('loadHub')), reason: 'the hub is already known');
    });

    testWidgets('the logins follow the loaded catalog: a new one without logins leaves only Google', (t) async {
      saved({});
      await pump(t, consoles: {'psx': _psx, 'switch': _switch}, section: SettingsSection.accounts);
      expect(find.text('not.ultranx.ru'), findsOneWidget);
      expect(find.text('Internet Archive'), findsOneWidget);

      app.state = const AppState(consoles: {'md': _plain, 'vault': _vault});
      await t.pumpAndSettle();
      expect(find.text('not.ultranx.ru'), findsNothing);
      expect(find.text('Internet Archive'), findsNothing);
      expect(find.text('Vault'), findsOneWidget);

      app.state = const AppState(consoles: {'md': _plain});
      await t.pumpAndSettle();
      expect(find.text('CATALOG LOGINS'), findsNothing);
      expect(find.text('Google Drive'), findsOneWidget);
    });

    testWidgets('a login shared by two consoles signs both in', (t) async {
      saved({});
      final c = await pump(t, consoles: {'switch': _switch, 'switch2': _switch2}, section: SettingsSection.accounts);
      await t.tap(find.text('not.ultranx.ru'));
      await t.pumpAndSettle();
      expect(find.byType(ConsoleAuthSetting), findsOneWidget);
      // The pasted-token fallback sits under Advanced.
      await t.tap(find.text('Advanced'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'tok123');
      await t.pump();
      await t.runAsync(() async {
        await t.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();
      expect(c.read(settingsProvider.notifier).getConsoleAuthToken('switch'), 'tok123');
      expect(c.read(settingsProvider.notifier).getConsoleAuthToken('switch2'), 'tok123');
      Navigator.of(t.element(find.byType(ConsoleAuthSetting))).pop();
      await t.pumpAndSettle();
      expect(find.text('Nintendo Switch, Switch Updates. Signed in'), findsOneWidget);
    });

    testWidgets('Google: Manage while signed in offers Sign out; signed out, Sign in with Google', (t) async {
      saved({});
      await pump(t, consoles: const {}, section: SettingsSection.accounts);
      await t.tap(find.text('Google Drive'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sign out'));
      await t.pumpAndSettle();
      expect(sync.calls, ['signOut']);

      sync.state = const SaveSyncState(hubKind: HubKind.none, googleAvailable: true);
      await t.pump();
      expect(find.text('Keeps saves in sync between devices. Not signed in'), findsOneWidget);
      await t.tap(find.text('Google Drive'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sign in with Google'));
      await t.pumpAndSettle();
      expect(sync.calls, ['signOut', 'signIn']);
    });

    testWidgets('a console page no longer has its login', (t) async {
      saved({});
      final c = await pump(t, consoles: {'switch': _switch}, section: SettingsSection.consoles);
      expect(c, isNotNull);
      await t.tap(find.text('Nintendo Switch'));
      await t.pumpAndSettle();
      expect(find.text('AUTHENTICATION'), findsNothing);
      expect(find.byType(ConsoleAuthSetting), findsNothing);
    });

    testWidgets('Keys opens straight from its link, shows each file or Not set', (t) async {
      saved({'nszKeysPath': '/data/keys/prod.keys'});
      await pump(t, consoles: const {}, section: SettingsSection.keys);
      expect(find.text('Switch keys'), findsOneWidget);
      expect(find.text('prod.keys'), findsOneWidget);
      expect(find.text('boot9.bin or aes_keys.txt'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
    });

    testWidgets('a key sheet copies the chosen file into the app, and Remove forgets it', (t) async {
      final tmp = Directory.systemTemp.createTempSync('rt_keys');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final src = File(p.join(tmp.path, 'picked', 'boot9.bin'))
        ..createSync(recursive: true)
        ..writeAsStringSync('rom');
      debugPickKeyFile = (_, title) async {
        expect(title, KeyFile.boot9.pickTitle);
        return src.path;
      };
      debugKeysParent = () async => Directory(p.join(tmp.path, 'app'));
      addTearDown(() {
        debugPickKeyFile = null;
        debugKeysParent = null;
      });
      saved({});
      final c = await pump(t, consoles: const {}, section: SettingsSection.keys);
      await t.tap(find.text('boot9.bin or aes_keys.txt'));
      await t.pumpAndSettle();
      expect(find.text('Remove boot9.bin'), findsNothing);
      await t.runAsync(() async {
        await t.tap(find.text('Choose file'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      final stored = c.read(settingsProvider).boot9Path!;
      expect(stored, p.join(tmp.path, 'app', 'keys', 'boot9.bin'));
      expect(File(stored).readAsStringSync(), 'rom');
      expect(find.text('boot9.bin'), findsOneWidget); // the row's value

      await t.tap(find.text('boot9.bin or aes_keys.txt'));
      await t.pumpAndSettle();
      expect(find.text('Choose another file'), findsOneWidget);
      await t.tap(find.text('Remove boot9.bin'));
      await t.pumpAndSettle();
      expect(c.read(settingsProvider).boot9Path, isNull);
    });

    testWidgets('narrow: the summaries say which keys are set and how many accounts are signed in', (t) async {
      saved({'nszKeysPath': '/k/prod.keys', 'iaAccessKey': 'a', 'iaSecretKey': 'b'});
      await pump(t, consoles: {'psx': _psx, 'switch': _switch, 'switch2': _switch2}, size: const Size(400, 900));
      expect(find.text('Switch keys set, boot9 missing'), findsOneWidget);
      expect(find.text('3 accounts, 2 signed in'), findsOneWidget); // IA, the site, Google
    });

    testWidgets('narrow: a section link opens that section page', (t) async {
      saved({});
      await pump(t, consoles: const {}, section: SettingsSection.keys, size: const Size(400, 900));
      expect(find.widgetWithText(SettingsTopBar, 'Keys'), findsOneWidget);
      expect(find.text('Switch keys'), findsOneWidget);
    });

    testWidgets("a console's NSZ without keys links to Keys", (t) async {
      saved({
        'consoleSettings': {
          'nx': {'additionalHandler': 'nsz_decompress'},
        },
      });
      const nx = Console(id: 'nx', name: 'Switch', urls: [], gameFilesFormat: ['.nsz'], additionalHandler: GameHandler.nszDecompress);
      await pump(t, consoles: {'nx': nx}, section: SettingsSection.consoles);
      await t.tap(find.text('Switch'));
      await t.pumpAndSettle();
      await t.tap(find.text('Switch keys missing'));
      await t.pumpAndSettle();
      expect(find.text('boot9.bin or aes_keys.txt'), findsOneWidget);
      expect(find.widgetWithText(SettingsTopBar, 'Keys'), findsOneWidget);
    });

    testWidgets('a row that becomes changed keeps the d-pad focus', (t) async {
      saved({});
      const psx = Console(id: 'psx', name: 'PlayStation', urls: [], gameFilesFormat: ['.cue']);
      final c = await pump(t, consoles: {'psx': psx}, section: SettingsSection.consoles);
      await t.tap(find.text('PlayStation'));
      await t.pumpAndSettle();
      final row = find.ancestor(of: find.text('Group multi-disc games'), matching: find.byType(SettingsTile));
      Focus.of(t.element(find.text('Group multi-disc games'))).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(c.read(settingsProvider.notifier).changedKeys('psx'), contains('groupDiscs'));
      expect(find.descendant(of: row, matching: find.byType(ChangedChip)), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<SettingsTile>(), t.widget(row));
    });
  });
}
