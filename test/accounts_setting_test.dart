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

/// Dois addons no **mesmo** console de conta, mais um console sem conta. É o
/// caso que a tela tem que desenhar como duas linhas, e é o caso que uma
/// implementação chaveada por console desenharia como uma.
MergedCatalog _doisNoMesmo() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes},
      sources: {
        'switch': [
          ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true}),
          ConsoleSource(addonId: 'outro', url: 'https://outro/switch/', auth: {'requires_token': true}),
        ],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
      },
    );

/// Só o addon embutido, servindo um console que não pede conta.
MergedCatalog _semConta() => const MergedCatalog(
      consoles: {'snes': _snes},
      sources: {
        'snes': [ConsoleSource(addonId: kBuiltinAddonId, url: 'https://myrient/snes/')],
      },
    );

/// Store de memória, e não `AddonStore` em `Directory.systemTemp`: IO de disco
/// trava dentro de `testWidgets`. E sem `addTearDown(notifier.dispose)`, que
/// seria o segundo descarte depois do que o `StateNotifierProvider` já faz
/// quando a árvore cai. Ver a Task 22 para os dois.
Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final notifier = AddonNotifier(Future.value(FakeAddonStore(addons)), invalidarCache: () async {});
  await notifier.ready;
  return notifier;
}

Future<void> _abrir(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalogo,
  SecretVault? vault,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalogo ?? _doisNoMesmo()),
      vaultProvider.overrideWith((ref) async => VaultChoice(vault ?? MemoryVault(), encryptedAtRest: true)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AccountsSetting())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem addon que peça conta, sobra só o Internet Archive', (tester) async {
    final notifier = await _notifier(const [Addon(id: kBuiltinAddonId, name: 'Catálogo embutido')]);

    await _abrir(tester, notifier: notifier, catalogo: _semConta());

    expect(find.text('Internet Archive'), findsOneWidget);
    expect(find.byType(ConsoleAuthSetting), findsNothing);
  });

  testWidgets('cada par (addon, console) que pede conta vira um bloco', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    // Dois blocos, não um: o console é o mesmo e os segredos são dois.
    expect(find.text('myrient.erista.me'), findsOneWidget);
    expect(find.text('outro.org'), findsOneWidget);
    expect(find.textContaining('Switch'), findsNWidgets(2));
    // O SNES não pede conta e não aparece.
    expect(find.textContaining('SNES'), findsNothing);
  });

  testWidgets('a ordem dos blocos é a ordem de prioridade dos addons', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    final titulos = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
    expect(titulos.indexOf('outro.org') < titulos.indexOf('myrient.erista.me'), isTrue);
  });

  testWidgets('o formulário de dentro recebe o par certo', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);
    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();

    final formularios = tester.widgetList<ConsoleAuthSetting>(find.byType(ConsoleAuthSetting)).toList();
    expect(formularios.length, 1);
    expect(formularios.single.addonId, 'myrient');
    expect(formularios.single.console.id, 'switch');
  });

  testWidgets('o cofre vazio diz não conectado e o cofre cheio diz conectado', (tester) async {
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('outro', 'switch'), 'tok');
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
    ]);

    await _abrir(tester, notifier: notifier, vault: vault);

    expect(find.text('Switch: Not connected'), findsOneWidget);
    expect(find.text('Switch: Connected'), findsOneWidget);
  });

  testWidgets('salvar no formulário atualiza o subtítulo sem recarregar a tela', (tester) async {
    final vault = MemoryVault();
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier, vault: vault);
    expect(find.text('Switch: Not connected'), findsOneWidget);

    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'tok-novo');
    // Este quadro é obrigatório, e não é estilo. `enterText` não constrói
    // quadro nenhum: ele chama `showKeyboard`, manda o texto e termina em
    // `idle()`, que só completa um `Timer.run`. Quem marca `_dirty` é o
    // `onChanged` do campo, por `setState`, e o botão de Save é
    // `onPressed: _dirty ? _save : null`. Sem este `pump`, a árvore que o
    // `tap` encontra ainda foi construída com `_dirty` falso, o botão está
    // desabilitado, e **`tap` em botão desabilitado não levanta: não faz
    // nada**. O cofre ficaria vazio e a asserção de baixo acusaria a produção
    // por um defeito do teste.
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('myrient', 'switch')), 'tok-novo');
    expect(find.text('Switch: Connected'), findsOneWidget);
    expect(find.text('Switch: Not connected'), findsNothing);
  });

  testWidgets('remover o addon tira a conta dele da lista', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);
    expect(find.text('outro.org'), findsOneWidget);

    await notifier.remove('outro');
    await tester.pumpAndSettle();

    expect(find.text('outro.org'), findsNothing);
    expect(find.text('myrient.erista.me'), findsOneWidget);
  });
}
