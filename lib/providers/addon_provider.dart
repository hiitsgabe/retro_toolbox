import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';

final addonProvider = StateNotifierProvider<AddonNotifier, List<Addon>>((ref) {
  return AddonNotifier(AddonStore.open());
});

/// A ordem de prioridade das fontes, derivada da ordem da lista.
///
/// É o que alimenta o `sourcePriority` de `planFromEntries`
/// (`source_pick_service.dart:54`), o último critério de desempate da seção 6
/// do spec de UI. Derivado e não guardado: prioridade que fosse um campo
/// próprio poderia discordar da ordem que o usuário vê na tela.
final sourcePriorityProvider = Provider<List<String>>((ref) => [for (final addon in ref.watch(addonProvider)) addon.id]);

/// Do id do addon para o nome que o usuário escreveu ou que o catálogo trouxe.
///
/// A seção 7 do spec de UI pede "4.0 MB, Myrient", e `SourcePick.sourceId`
/// guarda `myrient_org_files`, que é chave de cofre e nome de arquivo. Mapa e
/// não busca linear porque a lista de outras fontes resolve um nome por linha.
///
/// Quem lê tem que tratar id ausente: o cache de jogo de um addon removido
/// sobrevive à remoção, e o `sourceId` dele não está mais na lista.
final addonNamesProvider = Provider<Map<String, String>>(
  (ref) => {for (final addon in ref.watch(addonProvider)) addon.id: addon.name},
);

/// A cobertura de cada addon, recalculada toda vez que a lista muda.
///
/// `ref.watch(addonProvider)` está ali pelo efeito e não pelo valor: a fusão
/// mora dentro do `CatalogService`, e é ela que muda quando o usuário instala,
/// remove ou arrasta.
///
/// **Sem teste, e de propósito.** `mergedCatalog()` chega em disco por
/// `path_provider`, que num teste sem plataforma não falha: ele devolve vazio
/// em silêncio. Um teste aqui afirmaria cobertura zero e passaria para sempre,
/// inclusive depois de a regra quebrar. O que tem teste é
/// `MergedCatalog.coverage()`, que é onde a regra mora. As telas das Tasks 22
/// e 23 sobrescrevem este provider.
final addonCoverageProvider = FutureProvider<Map<String, AddonCoverage>>((ref) async {
  ref.watch(addonProvider);
  return (await CatalogService().mergedCatalog()).coverage();
});

class AddonNotifier extends StateNotifier<List<Addon>> {
  final Future<AddonStore> _store;

  /// O que esquecer quando a lista muda. Entra por parâmetro porque o padrão
  /// passa por `path_provider`, que num teste sem plataforma lança; o teste
  /// passa uma função que só conta quantas vezes foi chamada.
  final Future<void> Function() _invalidarCache;

  /// Resolve quando a lista inicial chegou do disco.
  late final Future<void> ready;

  AddonNotifier(this._store, {Future<void> Function()? invalidarCache})
      : _invalidarCache = invalidarCache ?? CatalogService().invalidateForAddonChange,
        super(const []) {
    ready = _carregar();
  }

  Future<void> _carregar() async {
    final store = await _store;
    if (!mounted) return;
    state = store.load();
  }

  /// Instala, ou reinstala, um addon com o catálogo já baixado.
  ///
  /// Reinstalar mantém a posição (`upsertAddon`), e é por isso que corrigir a
  /// url de uma fonte não rebaixa a prioridade dela.
  Future<void> install(Addon addon, String catalogoJson) async {
    final store = await _store;
    await store.writeCatalog(addon.id, catalogoJson);
    final nova = upsertAddon(state, addon);
    await store.save(nova);
    await _invalidarCache();
    if (mounted) state = nova;
  }

  /// Tira o addon da lista e apaga o catálogo dele do disco.
  ///
  /// **Não** apaga o segredo do cofre. Reinstalar a mesma fonte tem que
  /// reencontrar o token, e é para isso que `Addon.idFromUrl` é estável. Quem
  /// apaga credencial é a tela de conta, por pedido explícito (Grupo 5).
  Future<void> remove(String id) async {
    final store = await _store;
    await store.deleteCatalog(id);
    final nova = removeAddon(state, id);
    await store.save(nova);
    await _invalidarCache();
    if (mounted) state = nova;
  }

  Future<void> reorder(int from, int to) async {
    final nova = reorderAddons(state, from, to);
    final store = await _store;
    await store.save(nova);
    await _invalidarCache();
    if (mounted) state = nova;
  }
}
