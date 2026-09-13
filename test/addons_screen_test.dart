import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/screens/addons_screen.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';

import 'support/fake_addon_store.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: ['https://other/ps2/']);

const _catalogFetched = '''
[{"name": "PS2", "urls": ["https://incoming.org/ps2/"]}]
''';

/// `myrient` covers two consoles and one needs an account; `other` covers one
/// and none do.
MergedCatalog _catalog() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes, 'ps2': _ps2},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true})],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
        'ps2': [ConsoleSource(addonId: 'other', url: 'https://other/ps2/')],
      },
    );

/// The fetcher used by cases that do not talk about the network. A top-level
/// function, not a literal in the `??`, because `fetch ?? (_) async => ...` does
/// not parse as it reads.
Future<String> _fetchDefault(String url) async => _catalogFetched;

/// A real notifier over an in-memory store: drag and install must pass through
/// `reorder` and `install`. Only disk is fake, since it hangs inside
/// `testWidgets`. No `addTearDown(notifier.dispose)`: the provider disposes it
/// when the tree falls, and a second dispose kills every case.
Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final notifier = AddonNotifier(Future.value(FakeAddonStore(addons)), invalidateCache: () async {});
  await notifier.ready;
  return notifier;
}

Future<void> _open(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalog,
  CatalogFetcher? fetch,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalog ?? _catalog()),
      catalogFetcherProvider.overrideWithValue(fetch ?? _fetchDefault),
      vaultProvider.overrideWith((ref) async => VaultChoice(MemoryVault(), encryptedAtRest: true)),
    ],
    child: const MaterialApp(home: AddonsScreen()),
  ));
  await tester.pumpAndSettle();
}

/// Fills the install dialog field and confirms.
Future<void> _install(WidgetTester tester, String url) async {
  await tester.tap(find.text('Install from URL'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), url);
  await tester.tap(find.text('Install'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists addons in priority order', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    final names = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(names.indexOf('myrient.erista.me'), lessThan(names.indexOf('other.org')));
  });

  testWidgets('each row summarizes coverage', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    expect(find.text('2 consoles'), findsOneWidget);
    expect(find.text('1 console'), findsOneWidget);
  });

  testWidgets('the account chip only shows on addons needing a credential', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    expect(find.text('account'), findsOneWidget);
  });

  testWidgets('addon with no coverage stays in the list', (tester) async {
    // `coverage()` omits an addon with no console; omitting it on screen would
    // be worse than showing zero: the user just installed a source and, not
    // seeing it, installs again.
    final notifier = await _notifier(const [Addon(id: 'incoming', name: 'incoming.org', url: 'https://incoming.org/c.json')]);

    await _open(tester, notifier: notifier);

    expect(find.text('incoming.org'), findsOneWidget);
    expect(find.text('No console'), findsOneWidget);
  });

  testWidgets('empty list invites installing', (tester) async {
    final notifier = await _notifier(const []);

    await _open(tester, notifier: notifier);

    expect(find.text('No addons installed.'), findsOneWidget);
    expect(find.text('Install from URL'), findsOneWidget);
  });

  testWidgets('tapping a row opens the detail', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);
    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();

    expect(find.byType(AddonDetailScreen), findsOneWidget);
  });

  testWidgets('dragging reorders and the new order persists', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    // Drag the handle (not the row): use a hand-driven gesture with generous
    // distance — tester.drag skips the start listener and a short drag silently fails.
    final handle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kLongPressTimeout);
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(notifier.state.map((a) => a.id), ['other', 'myrient']);
  });

  testWidgets('installing from URL appends the addon', (tester) async {
    final notifier = await _notifier(const []);

    await _open(tester, notifier: notifier);
    await _install(tester, 'https://incoming.org/catalog.json');

    expect(notifier.state.map((a) => a.id), [Addon.idFromUrl('https://incoming.org/catalog.json')]);
  });

  testWidgets('a url returning no catalog shows the error and does not install', (tester) async {
    final notifier = await _notifier(const []);

    await _open(tester, notifier: notifier, fetch: (_) async => '<html>login</html>');
    await _install(tester, 'https://incoming.org/catalog.json');

    expect(notifier.state, isEmpty);
    expect(find.textContaining('Could not install'), findsOneWidget);
  });
}
