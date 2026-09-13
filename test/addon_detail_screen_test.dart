import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

import 'support/fake_addon_store.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: ['https://other/ps2/']);

/// Two addons over three consoles: `myrient` serves Switch (with account) and
/// SNES, `other` serves PS2. The `myrient` screen must not show PS2.
MergedCatalog _catalog() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes, 'ps2': _ps2},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true})],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
        'ps2': [ConsoleSource(addonId: 'other', url: 'https://other/ps2/')],
      },
    );

/// A real `AddonNotifier` over an in-memory store: the Remove case needs the
/// removal to pass through `AddonNotifier.remove`. Only disk is fake, because
/// disk IO hangs inside `testWidgets`.
///
/// No `addTearDown(notifier.dispose)`: the `StateNotifierProvider` disposes it
/// when the tree falls, and a second dispose kills every case. `app_settings`
/// seeded with `{}` so settings load does not fall into the plugin directory
/// branch.
Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final notifier = AddonNotifier(Future.value(FakeAddonStore(addons)), invalidateCache: () async {});
  await notifier.ready;
  return notifier;
}

/// Pushes the screen over an empty home. Pushed, not as `home`, because
/// `Navigator.pop` on the root route is a no-op: the Remove case would pass
/// without proving the screen closes.
Future<void> _open(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalog,
  String addonId = 'myrient',
  SecretVault? vault,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalog ?? _catalog()),
      vaultProvider.overrideWith((ref) async => VaultChoice(vault ?? MemoryVault(), encryptedAtRest: true)),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddonDetailScreen(addonId: addonId)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the name and source url', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient.erista.me/catalog.json')]);

    await _open(tester, notifier: notifier);

    expect(find.text('myrient.erista.me'), findsWidgets);
    expect(find.text('https://myrient.erista.me/catalog.json'), findsOneWidget);
  });

  testWidgets('addon without url shows the source in words', (tester) async {
    // The built-in and file-opened catalogs have no address; an empty url field
    // would make a normal case look broken.
    final notifier = await _notifier(const [Addon(id: kBuiltinAddonId, name: 'Built-in catalog')]);

    await _open(tester, notifier: notifier, addonId: kBuiltinAddonId);

    expect(find.text('Built-in catalog'), findsWidgets);
    expect(find.text('Installed with the app'), findsOneWidget);
  });

  testWidgets('coverage lists only this addon\'s consoles', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);

    expect(find.text('2 consoles'), findsOneWidget);
    expect(find.text('Switch'), findsWidgets);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('PS2'), findsNothing);
  });

  testWidgets('addon covering nothing yet shows zero and does not crash', (tester) async {
    // `coverage()` omits an addon with no console, so this is the missing-key
    // path, not the empty-list one: the state of a freshly installed addon
    // whose catalog is not read yet.
    final notifier = await _notifier(const [Addon(id: 'incoming', name: 'incoming.org', url: 'https://incoming.org/c.json')]);

    await _open(tester, notifier: notifier, addonId: 'incoming');

    expect(find.text('No console'), findsOneWidget);
    expect(find.byType(ConsoleAuthSetting), findsNothing);
  });

  testWidgets('only the account-needing console gets a form', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);

    final forms = tester.widgetList<ConsoleAuthSetting>(find.byType(ConsoleAuthSetting)).toList();
    expect(forms.length, 1);
    expect(forms.single.console.id, 'switch');
    // `addonId` stores the token under the right pair. Passing the built-in here
    // compiles and the Myrient token lands in the built-in drawer.
    expect(forms.single.addonId, 'myrient');
  });

  testWidgets('priority shows the position in the list', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: kBuiltinAddonId, name: 'Built-in catalog'),
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('cancelling removal does not remove', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(notifier.state.length, 1);
    expect(find.byType(AddonDetailScreen), findsOneWidget);
  });

  testWidgets('confirming removes and closes the screen', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    // The dialog button label differs from the screen's on purpose: with both
    // reading "Remove", this tap would match two widgets and die ambiguous.
    await tester.tap(find.text('Remove addon'));
    await tester.pumpAndSettle();

    expect(notifier.state, isEmpty);
    expect(find.byType(AddonDetailScreen), findsNothing);
  });
}
