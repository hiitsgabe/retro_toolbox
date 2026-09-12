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

const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://exemplo.org/snes/'], auth: {'requires_token': true});

/// `Scaffold` porque o widget chama `ScaffoldMessenger` ao salvar, e o
/// `app_settings` semeado com `{}` pelo mesmo motivo do `addon_token_test`:
/// sem a chave a carga cai no ramo que pergunta diretório por plugin.
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
  testWidgets('sem token guardado, mostra o campo para digitar', (tester) async {
    await tester.pumpWidget(_host(MemoryVault()));
    await tester.pumpAndSettle();

    expect(find.text('Bearer token'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets('com token no cofre, mostra assinado', (tester) async {
    // A leitura é assíncrona, então o estado inicial é carregando e só depois
    // vira "Signed in". Sem o `pumpAndSettle`, este caso passaria a ver o
    // formulário vazio e a afirmar o contrário do que o usuário vê.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken(kBuiltinAddonId, 'snes'), 'tok');

    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
  });

  testWidgets('salvar grava na chave do par (addon, console)', (tester) async {
    final vault = MemoryVault();
    await tester.pumpWidget(_host(vault, addonId: 'ultranx'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-ultranx');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), 'tok-ultranx');
  });

  testWidgets('o mesmo console em dois addons não divide token', (tester) async {
    // O que esta Task existe para garantir. O usuário tem conta no UltraNX e
    // não tem no embutido, e os dois servem `snes`.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'tok-ultranx');

    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsNothing);
    expect(find.text('Bearer token'), findsOneWidget);
  });

  testWidgets('deslogar apaga a chave do par', (tester) async {
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'tok-ultranx');

    await tester.pumpWidget(_host(vault, addonId: 'ultranx'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
    expect(find.text('Bearer token'), findsOneWidget);
  });

  testWidgets('o token do embutido continua chegando no espelho das settings', (tester) async {
    // O espelho é o que mantém de pé `consoleHasToken` e os `_authHeaders` de
    // LAN. Salvar pela tela tem que continuar alimentando os dois.
    final vault = MemoryVault();
    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-embutido');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(_container(tester).read(settingsProvider).consoleSettings['snes']?.authToken, 'tok-embutido');
  });
}
