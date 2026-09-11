import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_match_model.dart';
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
    // Uma entrada só entra em `planFromEntries`, e ela sai como exatamente uma
    // escolha ou exatamente uma falha. O `else if` lá embaixo existe para não
    // haver um `.first` numa lista que o compilador não garante.
    final falha = plan.failures.firstOrNull;
    final outras = _outrasFontes(entry, pick);

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
          ] else if (falha != null) ...[
            const SizedBox(height: 16),
            _SemFonte(reason: falha.reason),
          ],
          if (outras.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OutrasFontes(sources: outras),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  pick.filename,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _kTipoFonte,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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

/// O tipo de fonte, que nesta fatia é um só.
///
/// Toda fonte vem da listagem HTTP do console. `SEED` e `RD` da seção 7 do
/// spec de UI chegam quando o addon declarar o tipo (fatia 4 e fatia 6). É
/// constante em vez de literal solto para o dia em que virar campo.
const _kTipoFonte = 'HTTP';

/// As fontes que não ganharam o destaque, na ordem em que a fonte as deu.
///
/// Tira **uma** cópia da vencedora, não todas as de mesmo nome: duas fontes
/// podem servir arquivos homônimos de tamanhos diferentes, e sumir com as duas
/// esconderia uma fonte real. Sem escolha nenhuma, devolve tudo, porque aí
/// nenhuma delas é "a outra" e esconder o que existe deixaria a faixa de
/// "sem fonte" parecendo mentira.
List<MatchedSource> _outrasFontes(PackGridEntry entry, SourcePick? pick) {
  if (pick == null) return entry.sources;

  final outras = <MatchedSource>[];
  var jaTirou = false;
  for (final source in entry.sources) {
    final ehAVencedora = !jaTirou &&
        source.filename == pick.filename &&
        source.size == pick.size &&
        source.sourceId == pick.sourceId;
    if (ehAVencedora) {
      jaTirou = true;
      continue;
    }
    outras.add(source);
  }
  return outras;
}

String _rotuloOutras(int quantas) => quantas == 1 ? 'outra fonte' : 'outras $quantas fontes';

/// A confiança do **casamento**, que não é a verificação por CRC.
///
/// Ver a "Segunda decisão travada" do plano da fatia 3: são dois eixos e eles
/// não se misturam. A Task 18 acrescenta o estado de CRC como mais um pedaço
/// da mesma linha, sem tirar este.
String _rotuloConfianca(MatchConfidence confidence) => switch (confidence) {
      MatchConfidence.confirmed => 'casamento confirmado',
      MatchConfidence.likely => 'casamento provável',
      MatchConfidence.guess => 'casamento no chute',
    };

/// A faixa que substitui o card quando não há o que baixar.
///
/// O texto vem de `PickFailure.reason`, ou seja da mesma regra que a folha de
/// lote usa. A tela não inventa motivo próprio.
///
/// Falta aqui o atalho para a tela de addons que a seção 7 pede. A tela de
/// addons é a fatia 4; quando ela existir, o botão entra neste widget.
class _SemFonte extends StatelessWidget {
  final String reason;

  const _SemFonte({required this.reason});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(reason, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// A lista colapsada da seção 7. Informativa: o botão Baixar por linha é o
/// estado "verificação impossível" da seção 8, que é a Task 18.
class _OutrasFontes extends StatelessWidget {
  final List<MatchedSource> sources;

  const _OutrasFontes({required this.sources});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // `ExpansionTile` desenha uma divisória em cima e outra embaixo assim
      // que abre, e dentro de um `ListView` de cards isso vira duas linhas
      // soltas no meio da tela.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          _rotuloOutras(sources.length),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        children: [for (final source in sources) _LinhaFonte(source: source)],
      ),
    );
  }
}

class _LinhaFonte extends StatelessWidget {
  final MatchedSource source;

  const _LinhaFonte({required this.source});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source.filename, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            // Os cinco pedaços que a seção 7 pede, nesta ordem.
            '${formatBytes(source.size)}, ${source.sourceId}, '
            '$_kTipoFonte, ${_rotuloConfianca(source.confidence)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
