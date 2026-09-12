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
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: ['https://outro/ps2/']);

const _catalogoBaixado = '''
[{"name": "PS2", "urls": ["https://novo.org/ps2/"]}]
''';

/// `myrient` cobre dois consoles e um deles pede conta; `outro` cobre um e
/// nenhum pede.
MergedCatalog _catalogo() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes, 'ps2': _ps2},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true})],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
        'ps2': [ConsoleSource(addonId: 'outro', url: 'https://outro/ps2/')],
      },
    );

/// O fetcher que os casos que não falam de rede usam.
///
/// Função de topo e não literal no `??`: `fetch ?? (_) async => ...` não
/// parseia como se lê, porque o `=>` come o resto da expressão.
Future<String> _fetchPadrao(String url) async => _catalogoBaixado;

/// O notifier é o de verdade, sobre um store de memória: o arrasto e a
/// instalação têm que atravessar `reorder` e `install`, que chamam `save` e
/// `writeCatalog`. Falso é só o disco, que trava dentro de `testWidgets`.
///
/// Sem `addTearDown(notifier.dispose)` pelo mesmo motivo da Task 22: quem
/// descarta é o `StateNotifierProvider` quando a árvore cai, e um segundo
/// `dispose` mata todos os casos.
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
  CatalogFetcher? fetch,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalogo ?? _catalogo()),
      catalogFetcherProvider.overrideWithValue(fetch ?? _fetchPadrao),
      vaultProvider.overrideWith((ref) async => VaultChoice(MemoryVault(), encryptedAtRest: true)),
    ],
    child: const MaterialApp(home: AddonsScreen()),
  ));
  await tester.pumpAndSettle();
}

/// Preenche o campo do diálogo de instalação e confirma.
Future<void> _instalar(WidgetTester tester, String url) async {
  await tester.tap(find.text('Instalar de URL'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), url);
  await tester.tap(find.text('Instalar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista os addons na ordem da prioridade', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    final nomes = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(nomes.indexOf('myrient.erista.me'), lessThan(nomes.indexOf('outro.org')));
  });

  testWidgets('cada linha resume a cobertura', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('2 consoles'), findsOneWidget);
    expect(find.text('1 console'), findsOneWidget);
  });

  testWidgets('o chip de conta só aparece em quem exige credencial', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('conta'), findsOneWidget);
  });

  testWidgets('addon sem cobertura não some da lista', (tester) async {
    // `coverage()` omite o addon sem console, e omitir na tela seria pior que
    // mostrar zero: o usuário acabou de instalar uma fonte e ela não aparece,
    // então ele instala de novo.
    final notifier = await _notifier(const [Addon(id: 'novo', name: 'novo.org', url: 'https://novo.org/c.json')]);

    await _abrir(tester, notifier: notifier);

    expect(find.text('novo.org'), findsOneWidget);
    expect(find.text('Nenhum console'), findsOneWidget);
  });

  testWidgets('lista vazia convida a instalar', (tester) async {
    final notifier = await _notifier(const []);

    await _abrir(tester, notifier: notifier);

    expect(find.text('Nenhum addon instalado.'), findsOneWidget);
    expect(find.text('Instalar de URL'), findsOneWidget);
  });

  testWidgets('tocar na linha abre o detalhe', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _abrir(tester, notifier: notifier);
    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();

    expect(find.byType(AddonDetailScreen), findsOneWidget);
  });

  testWidgets('arrastar reordena e a nova ordem persiste', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'outro', name: 'outro.org', url: 'https://outro.org/c.json'),
    ]);

    await _abrir(tester, notifier: notifier);

    // Na alça e não na linha: a linha inteira é um `ListTile` com `onTap` que
    // abre o detalhe, e arrastar por ela abriria a tela em vez de reordenar.
    //
    // Gesto na mão e não `tester.drag`: o `ReorderableDragStartListener` usa
    // `ImmediateMultiDragGestureRecognizer`, que precisa do `moveBy` em um
    // quadro próprio para o reorder começar. Com `drag` o teste passa ou falha
    // conforme o tamanho da linha, que é a pior espécie de teste.
    //
    // A distância é folgada de propósito. Medido nesta tela: 100, 120 e 137 px
    // não trocam nada e 150 px troca, porque o `ReorderableListView` só
    // remaneja quando o item arrastado ultrapassa o vizinho inteiro, e as duas
    // linhas têm 74 e 72 px. Um gesto curto falha sem erro nenhum: a lista fica
    // intacta e a asserção acusa a ordem original, sem dizer que o gesto é que
    // foi curto. Com duas linhas, passar do fim dá no mesmo que trocar, então a
    // folga não custa precisão.
    final alca = find.byIcon(Icons.drag_handle).first;
    final gesto = await tester.startGesture(tester.getCenter(alca));
    await tester.pump(kLongPressTimeout);
    await gesto.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesto.up();
    await tester.pumpAndSettle();

    expect(notifier.state.map((a) => a.id), ['outro', 'myrient']);
  });

  testWidgets('instalar de URL acrescenta o addon', (tester) async {
    final notifier = await _notifier(const []);

    await _abrir(tester, notifier: notifier);
    await _instalar(tester, 'https://novo.org/catalogo.json');

    expect(notifier.state.map((a) => a.id), [Addon.idFromUrl('https://novo.org/catalogo.json')]);
  });

  testWidgets('url que não devolve catálogo mostra o erro e não instala', (tester) async {
    final notifier = await _notifier(const []);

    await _abrir(tester, notifier: notifier, fetch: (_) async => '<html>login</html>');
    await _instalar(tester, 'https://novo.org/catalogo.json');

    expect(notifier.state, isEmpty);
    expect(find.textContaining('Não deu para instalar'), findsOneWidget);
  });
}
