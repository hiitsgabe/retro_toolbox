import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/addon_store.dart';

Future<AddonStore> _store(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('addon_provider_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(addons);
  return store;
}

/// Devolve o container já com a lista inicial carregada, mais o store e o
/// contador de invalidações.
///
/// No topo do arquivo, e não dentro de `main`, por causa do lint
/// `no_leading_underscores_for_local_identifiers`, que vem ligado no
/// `flutter_lints` e vale para função local. `addTearDown` continua legal aqui
/// porque quem chama é sempre um corpo de teste.
Future<({ProviderContainer container, AddonStore store, List<int> invalidacoes})> _montar(List<Addon> iniciais) async {
  final store = await _store(iniciais);
  final invalidacoes = <int>[];
  final container = ProviderContainer(overrides: [
    addonProvider.overrideWith((ref) => AddonNotifier(
          Future.value(store),
          invalidarCache: () async => invalidacoes.add(1),
        )),
  ]);
  addTearDown(container.dispose);
  await container.read(addonProvider.notifier).ready;
  return (container: container, store: store, invalidacoes: invalidacoes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('carrega a lista do store no boot', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
  });

  test('install acrescenta no fim e persiste', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A')]);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'b', name: 'B'), '[]');
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
    expect(m.store.load().map((x) => x.id), ['a', 'b']);
  });

  test('install do mesmo id substitui sem mudar a posição', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'a', name: 'A corrigido'), '[]');
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
    expect(m.container.read(addonProvider).first.name, 'A corrigido');
  });

  test('install grava o catálogo no arquivo do addon', () async {
    final m = await _montar(const []);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'a', name: 'A'), '[{"name":"SNES"}]');
    expect(await m.store.readCatalog('a'), '[{"name":"SNES"}]');
  });

  test('remove tira da lista e persiste', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).remove('a');
    expect(m.container.read(addonProvider).map((x) => x.id), ['b']);
    expect(m.store.load().map((x) => x.id), ['b']);
  });

  test('remove apaga o arquivo de catálogo do addon', () async {
    final m = await _montar(const []);
    final notifier = m.container.read(addonProvider.notifier);
    await notifier.install(const Addon(id: 'a', name: 'A'), '[]');
    await notifier.remove('a');
    expect(await m.store.readCatalog('a'), isNull);
  });

  test('reorder aplica a semântica do ReorderableListView e persiste', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B'), Addon(id: 'c', name: 'C')]);
    await m.container.read(addonProvider.notifier).reorder(0, 3);
    expect(m.container.read(addonProvider).map((x) => x.id), ['b', 'c', 'a']);
    expect(m.store.load().map((x) => x.id), ['b', 'c', 'a']);
  });

  test('install e remove invalidam o cache, reorder também', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    final notifier = m.container.read(addonProvider.notifier);
    await notifier.install(const Addon(id: 'c', name: 'C'), '[]');
    await notifier.remove('a');
    await notifier.reorder(0, 2);
    expect(m.invalidacoes.length, 3);
  });

  test('sourcePriority devolve os ids na ordem da lista', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    expect(m.container.read(sourcePriorityProvider), ['a', 'b']);
  });

  test('sourcePriority acompanha o arrasto', () async {
    final m = await _montar(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).reorder(1, 0);
    expect(m.container.read(sourcePriorityProvider), ['b', 'a']);
  });

  test('addonNames mapeia cada id para o nome do addon', () async {
    final m = await _montar(const [
      Addon(id: 'myrient', name: 'Myrient'),
      Addon(id: kBuiltinAddonId, name: 'Catálogo embutido'),
    ]);

    expect(m.container.read(addonNamesProvider), {
      'myrient': 'Myrient',
      kBuiltinAddonId: 'Catálogo embutido',
    });
  });
}
