import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/app_state_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/widgets/header/header.dart';
import 'package:roms_downloader/widgets/game_list/game_list.dart';
import 'package:roms_downloader/widgets/game_grid/game_grid.dart';
import 'package:roms_downloader/widgets/game_grid/game_cover_flow.dart';
import 'package:roms_downloader/widgets/footer/footer.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/services/task_queue_service.dart';
import 'package:roms_downloader/widgets/game_grid/batch_confirm_sheet.dart';
import 'package:roms_downloader/screens/settings_screen.dart';
import 'package:roms_downloader/widgets/common/hammer_loader.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/screens/game_detail_screen.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// O plano do lote, pelo modo corrente.
  ///
  /// Os dois ramos devolvem o mesmo tipo e caem na mesma folha, no mesmo
  /// enfileiramento e na mesma limpeza de seleção. Se você se pegar
  /// escrevendo um segundo `showModalBottomSheet` aqui, parou no lugar
  /// errado: o que varia entre os modos é só como o `BatchPlan` nasce.
  BatchPlan _planoDaSelecao(Set<String> selecionadas) {
    if (ref.read(gridModeProvider) == GridMode.pack) {
      // A regra da seção 6, a mesma que escolhe o destaque da tela de
      // detalhe. `allPackEntriesProvider` e não `packGridEntriesProvider`:
      // ver o Problema 1 no topo desta Task.
      return planFromEntries(
        entriesForSelection(ref.read(allPackEntriesProvider), selecionadas),
        preferredRegions: ref.read(preferredRegionsProvider),
        resolveGame: ref.read(gameResolverProvider),
      );
    }
    // MODO FONTE: cada chave já é um arquivo, nada a escolher.
    final games = ref.read(catalogProvider).games;
    return planFromGames(games.where((game) => selecionadas.contains(game.gameId)).toList());
  }

  /// Abre a folha da seção 6, e só enfileira o que voltar dela.
  Future<void> _confirmarLote(Set<String> selecionadas) async {
    var plano = _planoDaSelecao(selecionadas);
    // Um plano só de falhas **não** é vazio: a folha abre para dizer por que
    // nada vai ser baixado. Ver `BatchPlan.isEmpty`, na Task 4.
    if (plano.isEmpty) return;

    final confirmado = await showModalBottomSheet<BatchPlan>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => BatchConfirmSheet(
          plan: plano,
          onConfirm: (p) => Navigator.of(sheetContext).pop(p),
          onRemove: (gameId) => setSheetState(() => plano = plano.withoutPick(gameId)),
        ),
      ),
    );
    if (confirmado == null || !mounted) return;

    await TaskQueueService.startDownloads(
      ref,
      context,
      confirmado.picks.map((pick) => pick.game).toList(),
      ref.read(appStateProvider).selectedConsole?.id,
    );
    if (!mounted) return;
    ref.read(catalogProvider.notifier).clearSelection();
  }

  /// Empurra a tela de detalhe.
  ///
  /// A grade não navega (Task 12) e a tela não conhece a fila (Task 15). Os
  /// dois cabos soltos se encontram aqui, e é o único lugar em que se
  /// encontram.
  void _abrirDetalhe(PackGridEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDetailScreen(
        entry: entry,
        onDownload: _baixarUm,
        onBatchDownload: () => _confirmarLote(_selecaoDoModo),
      ),
    ));
  }

  /// A seleção do modo corrente, lida na hora do toque.
  ///
  /// O `build` calcula a mesma coisa para a contagem da barra, mas o lote lê
  /// aqui, e não daquele valor, porque a folha pode ser aberta pela tela de
  /// detalhe, que fica **em cima** desta. Ler no momento do toque tira a
  /// pergunta "aquele valor ainda é o de agora" do caminho.
  Set<String> get _selecaoDoModo => selectionKeysFor(
        ref.read(catalogProvider).selectedGames,
        pack: ref.read(gridModeProvider) == GridMode.pack,
      );

  /// Uma escolha só, vinda da tela de detalhe, vai direto para a fila.
  ///
  /// Sem folha de confirmação, e isso é decisão, não esquecimento: a tela de
  /// detalhe **é** a confirmação. Ela já mostra o arquivo escolhido, o
  /// tamanho, o motivo por extenso e o veredito do CRC. Abrir por cima disso
  /// uma folha de lote de um item só seria perguntar duas vezes a mesma
  /// coisa. A folha existe para o lote, onde o usuário não viu escolha
  /// nenhuma antes de apertar Baixar.
  Future<void> _baixarUm(SourcePick pick) async {
    await TaskQueueService.startDownloads(
      ref,
      context,
      [pick.game],
      ref.read(appStateProvider).selectedConsole?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final appStateNotifier = ref.read(appStateProvider.notifier);
    final loadingStatus = ref.watch(catalogProvider.select((s) => s.loadingStatus));
    final errorMessage = ref.watch(catalogProvider.select((s) => s.errorMessage));
    final gridMode = ref.watch(gridModeProvider);
    final selecionadas = selectionKeysFor(
      ref.watch(catalogProvider.select((s) => s.selectedGames)),
      pack: gridMode == GridMode.pack,
    );

    return Scaffold(
      body: Column(
        children: [
          Header(
            consoles: appState.consolesList,
            selectedConsole: appState.selectedConsole,
            onConsoleSelect: appStateNotifier.selectConsole,
          ),
          Expanded(
            child: appState.consolesList.isEmpty && !appState.loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dataset_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          const Text('No catalog configured', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 8),
                          const Text(
                            'Add a console catalog to get started: import a JSON file or load one from a URL.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen(consoleId: null)),
                            ),
                            icon: const Icon(Icons.settings),
                            label: const Text('Open Settings'),
                          ),
                        ],
                      ),
                    ),
                  )
                : appState.loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HammerLoader(),
                        SizedBox(height: 16),
                        Text(loadingStatus.isEmpty ? 'Loading (this can take a while)...' : '$loadingStatus...'),
                      ],
                    ),
                  )
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                              const SizedBox(height: 12),
                              Text(errorMessage, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    : switch (gridMode) {
                        GridMode.pack => PackGrid(onOpenGame: _abrirDetalhe),
                        GridMode.source => switch (appState.viewMode) {
                            ViewMode.grid => GameGrid(),
                            ViewMode.coverflow => const GameCoverFlow(),
                            ViewMode.list => GameList(),
                          },
                      },
          ),
          SelectionBar(
            count: selecionadas.length,
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: () => _confirmarLote(_selecaoDoModo),
          ),
          Footer(),
        ],
      ),
    );
  }
}
