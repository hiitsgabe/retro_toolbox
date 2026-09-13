import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/accounts_setting.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

import 'support/fake_addon_store.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);

/// Two addons on the same account console, plus one console with no account: the
/// case a console-keyed implementation would wrongly draw as a single row.
MergedCatalog _twoInSame() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes},
      sources: {
        'switch': [
          ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true}),
          ConsoleSource(addonId: 'other', url: 'https://other/switch/', auth: {'requires_token': true}),
        ],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
      },
    );

/// Only the built-in addon, serving a console that needs no account.
MergedCatalog _noAccount() => const MergedCatalog(
      consoles: {'snes': _snes},
      sources: {
        'snes': [ConsoleSource(addonId: kBuiltinAddonId, url: 'https://myrient/snes/')],
      },
    );

/// In-memory store, not `AddonStore` in `Directory.systemTemp`: disk IO hangs
/// inside `testWidgets`. No `addTearDown(notifier.dispose)`, which would be a
/// second dispose after the provider tears down.
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
  SecretVault? vault,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalog ?? _twoInSame()),
      vaultProvider.overrideWith((ref) async => VaultChoice(vault ?? MemoryVault(), encryptedAtRest: true)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AccountsSetting())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no account-needing addon leaves only Internet Archive', (tester) async {
    final notifier = await _notifier(const [Addon(id: kBuiltinAddonId, name: 'Built-in catalog')]);

    await _open(tester, notifier: notifier, catalog: _noAccount());

    expect(find.text('Internet Archive'), findsOneWidget);
    expect(find.byType(ConsoleAuthSetting), findsNothing);
  });

  testWidgets('each account-needing (addon, console) pair becomes a block', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    // Two blocks, not one: same console, two secrets.
    expect(find.text('myrient.erista.me'), findsOneWidget);
    expect(find.text('other.org'), findsOneWidget);
    expect(find.textContaining('Switch'), findsNWidgets(2));
    // SNES needs no account and does not appear.
    expect(find.textContaining('SNES'), findsNothing);
  });

  testWidgets('block order follows addon priority order', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    final titles = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
    final first = titles.indexOf('other.org');
    final second = titles.indexOf('myrient.erista.me');
    // `indexOf` returns -1 when absent, so assert presence before comparing:
    // otherwise the case passes when the first block is missing from the tree.
    expect(first, isNonNegative);
    expect(second, isNonNegative);
    expect(first < second, isTrue);
  });

  testWidgets('inner form receives the right (addon, console) pair', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
    ]);

    await _open(tester, notifier: notifier);
    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();

    final forms = tester.widgetList<ConsoleAuthSetting>(find.byType(ConsoleAuthSetting)).toList();
    expect(forms.length, 1);
    expect(forms.single.addonId, 'myrient');
    expect(forms.single.console.id, 'switch');
  });

  testWidgets('empty vault shows not connected, filled vault shows connected', (tester) async {
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('other', 'switch'), 'tok');
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
    ]);

    await _open(tester, notifier: notifier, vault: vault);

    expect(find.text('Switch: Not connected'), findsOneWidget);
    expect(find.text('Switch: Connected'), findsOneWidget);
  });

  testWidgets('saving in the form updates the subtitle without reloading', (tester) async {
    final vault = MemoryVault();
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier, vault: vault);
    expect(find.text('Switch: Not connected'), findsOneWidget);

    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'tok-new');
    // Required: `enterText` builds no frame, so without this pump the Save
    // button is still disabled and tapping a disabled button is a no-op.
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('myrient', 'switch')), 'tok-new');
    expect(find.text('Switch: Connected'), findsOneWidget);
    expect(find.text('Switch: Not connected'), findsNothing);
  });

  testWidgets('removing the addon drops its account from the list', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
    ]);

    await _open(tester, notifier: notifier);
    expect(find.text('other.org'), findsOneWidget);

    await notifier.remove('other');
    await tester.pumpAndSettle();

    expect(find.text('other.org'), findsNothing);
    expect(find.text('myrient.erista.me'), findsOneWidget);
  });
}
