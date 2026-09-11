import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

/// A grade de MODO PACK: um tile por jogo do pacote.
///
/// Não substitui `GameGrid`, convive com ela. Quem escolhe qual das duas
/// desenhar é o `HomeScreen`, pelo `gridModeProvider` (Task 19).
class PackGrid extends ConsumerWidget {
  /// Chamado no toque curto de um tile. A grade não conhece `Navigator`: quem
  /// empurra a rota do detalhe é o `HomeScreen`.
  final void Function(PackGridEntry entry) onOpenGame;

  const PackGrid({super.key, required this.onOpenGame});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(packGridEntriesProvider);
    final index = ref.watch(sourceIndexProvider);
    final selected = ref.watch(catalogProvider.select((s) => s.selectedGames));
    final catalogNotifier = ref.read(catalogProvider.notifier);

    // Seção 4 do spec de UI: a visibilidade do checkbox é global e depende só
    // de haver seleção em curso. Com seleção vazia, capa limpa em todo tile.
    final selectionActive = selected.isNotEmpty;

    // Seção 3.2. Nesta fatia "nenhuma fonte" quer dizer "a listagem deste
    // console não casou com nenhum jogo do pacote". Na fatia 4 a condição
    // passa a ser "nenhum addon instalado cobre este console" e o texto fica.
    final semCobertura = (index?.matchedGameCount ?? 0) == 0;

    return Column(
      children: [
        if (semCobertura) const _SemCoberturaBanner(),
        Expanded(
          child: entries.isEmpty
              ? const _VazioDeBusca()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    // Proporção fixa, ao contrário de `GameGrid`, que mede a
                    // primeira capa da listagem. As capas do pacote vêm todas
                    // da mesma origem e já são consistentes, então medir seria
                    // um round-trip de imagem por troca de console, de graça.
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return PackGridItem(
                        key: ValueKey(entry.selectionKey),
                        title: entry.game.title,
                        coverUrl: entry.game.cover,
                        hasSource: entry.hasSource,
                        isSelected: selected.contains(entry.selectionKey),
                        selectionActive: selectionActive,
                        onTap: () => onOpenGame(entry),
                        onLongPress: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
                        onToggleSelection: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _SemCoberturaBanner extends StatelessWidget {
  const _SemCoberturaBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Nenhuma fonte cobre este console',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Os jogos aparecem para consulta, mas não há nada para baixar.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VazioDeBusca extends StatelessWidget {
  const _VazioDeBusca();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Nenhum jogo com esse nome',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
