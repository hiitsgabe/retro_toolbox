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
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: ['https://outro/ps2/']);

/// Dois addons servindo três consoles: `myrient` serve Switch (com conta) e
/// SNES, `outro` serve PS2. A tela do `myrient` não pode mostrar PS2.
MergedCatalog _catalogo() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes, 'ps2': _ps2},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true})],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
        'ps2': [ConsoleSource(addonId: 'outro', url: 'https://outro/ps2/')],
      },
    );

/// Um `AddonNotifier` de verdade sobre um store de memória.
///
/// O notifier é o real de propósito: o caso do "Remover" precisa que a remoção
/// atravesse `AddonNotifier.remove` e volte pela lista. O que é falso é só o
/// disco, porque IO de disco trava dentro de `testWidgets`, e `remove` chama
/// `deleteCatalog` de dentro do `pumpAndSettle`.
///
/// **Sem `addTearDown(notifier.dispose)`, e isso é deliberado.** Quem descarta
/// é o Riverpod: `addonProvider` é um `StateNotifierProvider`, e um
/// `StateNotifierProvider` assume o ciclo de vida do notifier que o `create`
/// devolve, inclusive quando o `create` só repassa um que veio de fora. Ao fim
/// de um `testWidgets` o `flutter_test` desmonta a árvore, o `ProviderScope`
/// do `_abrir` cai junto e o `dispose` acontece ali. Um `addTearDown` seria o
/// segundo, e os oito casos morrem com `Bad state: Tried to use AddonNotifier
/// after dispose was called`.
///
/// `addon_install_test._notifier` **tem** essa linha e está certo, porque lá o
/// notifier não passa por provider nenhum. Este helper nasceu de uma cópia
/// daquele, e a linha é o que sobrou da cópia.
///
/// O `app_settings` semeado com `{}` é pelo mesmo motivo do
/// `console_auth_setting_test`: sem a chave, a carga das settings cai no ramo
/// que pergunta diretório por plugin.
Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final notifier = AddonNotifier(Future.value(FakeAddonStore(addons)), invalidarCache: () async {});
  await notifier.ready;
  return notifier;
}

/// Empilha a tela sobre uma home vazia.
///
/// Empilhada e não como `home` porque `Navigator.pop` na rota raiz é no-op: o
/// caso do "Remover" passaria sem provar que a tela fecha.
Future<void> _abrir(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalogo,
  String addonId = 'myrient',
  SecretVault? vault,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalogo ?? _catalogo()),
      vaultProvider.overrideWith((ref) async => VaultChoice(vault ?? MemoryVault(), encryptedAtRest: true)),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddonDetailScreen(addonId: addonId)),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra o nome e a url de origem', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient.erista.me/catalogo.json')]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('myrient.erista.me'), findsWidgets);
    expect(find.text('https://myrient.erista.me/catalogo.json'), findsOneWidget);
  });

  testWidgets('addon sem url mostra a origem por extenso', (tester) async {
    // O embutido e o catálogo aberto de arquivo não têm endereço. Um campo de
    // url vazio faria a tela parecer quebrada num caso que é normal.
    final notifier = await _notifier(const [Addon(id: kBuiltinAddonId, name: 'Catálogo embutido')]);

    await _abrir(tester, notifier: notifier, addonId: kBuiltinAddonId);

    expect(find.text('Catálogo embutido'), findsWidgets);
    expect(find.text('Instalado com o app'), findsOneWidget);
  });

  testWidgets('a cobertura lista só os consoles deste addon', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('2 consoles'), findsOneWidget);
    expect(find.text('Switch'), findsWidgets);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('PS2'), findsNothing);
  });

  testWidgets('addon que ainda não cobre nada mostra zero e não quebra', (tester) async {
    // `MergedCatalog.coverage()` **omite** o addon sem console (Task 18), então
    // este é o caminho do mapa sem a chave, não o da lista vazia. É o estado
    // real de um addon recém instalado cujo catálogo ainda não foi lido.
    final notifier = await _notifier(const [Addon(id: 'novo', name: 'novo.org', url: 'https://novo.org/c.json')]);

    await _abrir(tester, notifier: notifier, addonId: 'novo');

    expect(find.text('Nenhum console'), findsOneWidget);
    expect(find.byType(ConsoleAuthSetting), findsNothing);
  });

  testWidgets('só o console que pede conta ganha formulário', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);

    final formularios = tester.widgetList<ConsoleAuthSetting>(find.byType(ConsoleAuthSetting)).toList();
    expect(formularios.length, 1);
    expect(formularios.single.console.id, 'switch');
    // O `addonId` é o que faz o token ser guardado sob o par certo. Passar o
    // embutido aqui compila, a tela funciona, e o token do Myrient vai para a
    // gaveta do catálogo embutido.
    expect(formularios.single.addonId, 'myrient');
  });

  testWidgets('a prioridade mostra a posição na lista', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: kBuiltinAddonId, name: 'Catálogo embutido'),
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('2ª de 3'), findsOneWidget);
  });

  testWidgets('cancelar a remoção não remove', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(notifier.state.length, 1);
    expect(find.byType(AddonDetailScreen), findsOneWidget);
  });

  testWidgets('confirmar remove e fecha a tela', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    // O rótulo do botão do diálogo é diferente do da tela de propósito: com os
    // dois escritos "Remover", este `tap` acharia dois widgets e o teste
    // morreria em ambiguidade em vez de provar alguma coisa.
    await tester.tap(find.text('Remover addon'));
    await tester.pumpAndSettle();

    expect(notifier.state, isEmpty);
    expect(find.byType(AddonDetailScreen), findsNothing);
  });
}
