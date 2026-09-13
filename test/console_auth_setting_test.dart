import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://example.org/snes/'], auth: {'requires_token': true});

/// `Scaffold` because the widget calls `ScaffoldMessenger` on save, and
/// `app_settings` seeded with `{}` so settings load does not fall into the
/// plugin directory branch.
Widget _host(MemoryVault vault, {String addonId = kBuiltinAddonId}) {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  return ProviderScope(
    overrides: [
      vaultProvider.overrideWith((ref) async => VaultChoice(vault, encryptedAtRest: true)),
    ],
    child: MaterialApp(
      home: Scaffold(body: ConsoleAuthSetting(console: _snes, addonId: addonId)),
    ),
  );
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

void main() {
  testWidgets('with no stored token, shows the input field', (tester) async {
    await tester.pumpWidget(_host(MemoryVault()));
    await tester.pumpAndSettle();

    expect(find.text('Bearer token'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets('with a token in the vault, shows signed in', (tester) async {
    // The read is async, so without `pumpAndSettle` this case would see the
    // empty form and assert the opposite of what the user sees.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken(kBuiltinAddonId, 'snes'), 'tok');

    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
  });

  testWidgets('saving writes to the (addon, console) key', (tester) async {
    final vault = MemoryVault();
    await tester.pumpWidget(_host(vault, addonId: 'ultranx'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-ultranx');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), 'tok-ultranx');
  });

  testWidgets('the same console under two addons does not share a token', (tester) async {
    // The user has an UltraNX account and no built-in one, and both serve `snes`.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'tok-ultranx');

    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsNothing);
    expect(find.text('Bearer token'), findsOneWidget);
  });

  testWidgets('logging out deletes the pair key', (tester) async {
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'tok-ultranx');

    await tester.pumpWidget(_host(vault, addonId: 'ultranx'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
    expect(find.text('Bearer token'), findsOneWidget);
  });

  testWidgets('the built-in token still reaches the settings mirror', (tester) async {
    // The mirror is what keeps `consoleHasToken` and the LAN `_authHeaders`
    // alive. Saving via the screen must keep feeding both.
    final vault = MemoryVault();
    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-builtin');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(_container(tester).read(settingsProvider).consoleSettings['snes']?.authToken, 'tok-builtin');
  });
}
