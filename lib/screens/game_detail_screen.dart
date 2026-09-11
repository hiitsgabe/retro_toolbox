import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// A tela da seção 7 do spec de UI: um jogo, as fontes dele e o motivo da
/// escolha.
///
/// Não é bottom sheet e não é expansão inline. É rota.
class GameDetailScreen extends ConsumerWidget {
  final PackGridEntry entry;

  /// O que fazer quando o usuário aperta Baixar.
  ///
  /// A tela não conhece a fila, pelo mesmo motivo que `PackGrid` não conhece
  /// `Navigator`: `TaskQueueService.startDownloads` puxa o pipeline inteiro de
  /// download, e uma tela que o chama direto não se testa. Quem liga os dois é
  /// o `HomeScreen`.
  final void Function(SourcePick pick) onDownload;

  const GameDetailScreen({super.key, required this.entry, required this.onDownload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = entry.game;
    final chave = entry.selectionKey;
    final favorito = ref.watch(favoritesProvider).isFavorite(chave);
    final selecionado = ref.watch(catalogProvider.select((s) => s.selectedGames)).contains(chave);

    // A mesma regra do lote, com uma entrada só. Seção 6: uma regra só, dois
    // lugares. Não escreva uma escolha diferente aqui.
    final plan = planFromEntries(
      [entry],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: ref.watch(gameResolverProvider),
    );
    final pick = plan.picks.firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(game.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: favorito ? 'Tirar dos favoritos' : 'Favoritar',
            icon: Icon(
              favorito ? Icons.favorite : Icons.favorite_border,
              color: favorito ? Colors.red : null,
            ),
            onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(chave),
          ),
          Checkbox(
            value: selecionado,
            onChanged: (_) => ref.read(catalogProvider.notifier).toggleGameSelection(chave),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Topo(game: game, sistema: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (pick != null) ...[
            const SizedBox(height: 16),
            _Destaque(pick: pick, onDownload: () => onDownload(pick)),
          ],
        ],
      ),
    );
  }
}

class _Topo extends StatelessWidget {
  final PackGame game;
  final String sistema;

  const _Topo({required this.game, required this.sistema});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Só o que existe entra na linha, senão sobra vírgula solta num jogo sem
    // ano ou sem publisher, que é a maioria dos homebrews.
    final ficha = [
      sistema,
      if (game.year != null) '${game.year}',
      if ((game.publisher ?? '').isNotEmpty) game.publisher!,
      if ((game.genre ?? '').isNotEmpty) game.genre!,
    ].where((parte) => parte.isNotEmpty).join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _capa(context),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(ficha, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _capa(BuildContext context) {
    final url = game.cover;
    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.videogame_asset_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (context, _, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      errorListener: (_) {},
    );
  }
}

/// O card da versão escolhida. O motivo é a linha que não pode faltar.
class _Destaque extends StatelessWidget {
  final SourcePick pick;
  final VoidCallback onDownload;

  const _Destaque({required this.pick, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pick.filename, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '${formatBytes(pick.size)}, ${pick.sourceId}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(pick.reason, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onDownload, child: const Text('Baixar')),
          ),
        ],
      ),
    );
  }
}
