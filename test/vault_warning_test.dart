import 'dart:async';
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
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

import 'support/fake_addon_store.dart';

const _warning = 'Credentials are stored in plain text on this device.';

/// Seeds prefs before mounting anything that reads `settingsProvider`.
/// A top-level function because the last case does not use `_host` yet still
/// needs it, since it mounts `AddonDetailScreen` which reads `settingsProvider`.
void _seedPrefs() {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
}

Widget _host(Override vault, {Widget child = const VaultWarning()}) {
  _seedPrefs();
  return ProviderScope(
    overrides: [vault],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Override _vault({required bool encrypted}) =>
    vaultProvider.overrideWith((ref) async => VaultChoice(MemoryVault(), encryptedAtRest: encrypted));

void main() {
  testWidgets('non-encrypting vault warns', (tester) async {
    await tester.pumpWidget(_host(_vault(encrypted: false)));
    await tester.pumpAndSettle();

    expect(find.text(_warning), findsOneWidget);
  });

  testWidgets('encrypting vault warns nothing and takes no space', (tester) async {
    await tester.pumpWidget(_host(_vault(encrypted: true)));
    await tester.pumpAndSettle();

    expect(find.text(_warning), findsNothing);
    expect(tester.getSize(find.byType(VaultWarning)), Size.zero);
  });

  testWidgets('does not warn while the keyring is being probed', (tester) async {
    final pending = Completer<VaultChoice>();
    // Complete in teardown so the pending Completer does not leak a future.
    addTearDown(() => pending.complete(VaultChoice(MemoryVault(), encryptedAtRest: true)));

    await tester.pumpWidget(_host(vaultProvider.overrideWith((ref) => pending.future)));
    await tester.pump();

    expect(find.text(_warning), findsNothing);
  });

  testWidgets('no vault opened warns harder', (tester) async {
    // The `error` branch needs the fallback itself to throw; a missing keyring
    // is swallowed and arrives as `data` with `encryptedAtRest: false`.
    await tester.pumpWidget(_host(vaultProvider.overrideWith((ref) async => throw StateError('not even the fallback opened'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open any vault'), findsOneWidget);
  });

  testWidgets('the addon detail warns next to the account form', (tester) async {
    _seedPrefs();
    const console = Console(id: 'switch', name: 'Switch', urls: ['https://m/switch/'], auth: {'requires_token': true});
    const merged = MergedCatalog(
      consoles: {'switch': console},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://m/switch/', auth: {'requires_token': true})],
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _vault(encrypted: false),
        addonProvider.overrideWith((ref) => AddonNotifier(
              Future.value(FakeAddonStore(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://m/c.json')])),
              invalidateCache: () async {},
            )),
        mergedCatalogProvider.overrideWith((ref) async => merged),
      ],
      child: const MaterialApp(home: AddonDetailScreen(addonId: 'myrient')),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_warning), findsOneWidget);
  });
}
