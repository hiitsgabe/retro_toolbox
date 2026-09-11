import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/utils/formatters.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';

/// O tipo de fonte, que nesta fatia é um só.
///
/// Toda fonte vem da listagem HTTP do console. `SEED` e `RD` da seção 7 do
/// spec de UI chegam quando o addon declarar o tipo (fatia 4 e fatia 6). É
/// constante em vez de literal solto para o dia em que virar campo.
const _kTipoFonte = 'HTTP';

/// A tela das seções 7 e 8 do spec de UI: um jogo, as fontes dele, o motivo da
/// escolha e o que a verificação por CRC disse sobre cada uma.
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

  /// O que fazer quando o usuário aperta Baixar **na barra do rodapé**, que é
  /// o lote e não este jogo.
  ///
  /// Callback pelo mesmo motivo de [onDownload]: esta tela não conhece a fila
  /// nem a folha de confirmação. Quem liga é o `HomeScreen`.
  final VoidCallback onBatchDownload;

  const GameDetailScreen({
    super.key,
    required this.entry,
    required this.onDownload,
    required this.onBatchDownload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = entry.game;
    final chave = entry.selectionKey;
    final favorito = ref.watch(favoritesProvider).isFavorite(chave);
    final selecionadas = ref.watch(catalogProvider.select((s) => s.selectedGames));
    final selecionado = selecionadas.contains(chave);
    final resolver = ref.watch(gameResolverProvider);

    // Os vereditos são resolvidos **aqui**, uma vez, e descem como dado. Os
    // widgets filhos não veem `ref`: eles são burros como todo o resto desta
    // fatia. O `watch` por fonte é barato porque a família do Riverpod cacheia
    // por (fonte, arquivo).
    final verificadas = <VerifiedSource>[
      for (final source in entry.sources) (source: source, state: _estadoDe(ref, game.id, source)),
    ];
    final split = splitByVerification(verificadas);

    // A mesma regra do lote, com uma entrada só, sobre quem sobrou da
    // verificação. Seção 6: uma regra só, dois lugares.
    final plan = planFromEntries(
      [PackGridEntry(game: game, sources: [for (final v in split.eligible) v.source])],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: resolver,
    );

    final escolha = split.noCertainty ? null : plan.picks.firstOrNull;
    final vencedora = _vencedora(split.eligible, escolha);
    final outras = [
      for (final v in verificadas)
        if (!identical(v.source, vencedora?.source)) v,
    ];

    // A única string desta tela que não sai de `PickFailure`, e tem que ser: o
    // lote não verifica CRC, então a regra de lote não conhece este estado.
    // Não "conserte" isso movendo a string para o serviço.
    final faixa = split.eligible.isEmpty && split.discarded.isNotEmpty
        ? 'nenhuma fonte passou na verificação por CRC'
        : (split.noCertainty ? null : plan.failures.firstOrNull?.reason);

    void baixarFonte(VerifiedSource item) {
      final jogo = resolver(item.source);
      if (jogo == null) return;
      onDownload(SourcePick(
        gameId: chave,
        title: game.title,
        filename: item.source.filename,
        size: item.source.size,
        sourceId: item.source.sourceId,
        reason: 'escolhida por você, sem verificação possível',
        uncertain: true,
        game: jogo,
      ));
    }

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
      bottomNavigationBar: SelectionBar(
        // `pack: true` literal, e não lido do `gridModeProvider`: esta tela
        // só existe em MODO PACK, porque só `PackGrid` a empurra. Ler o modo
        // aqui daria a impressão falsa de que ela abre em MODO FONTE.
        count: selectionKeysFor(selecionadas, pack: true).length,
        onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
        onDownload: onBatchDownload,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Topo(game: game, sistema: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (escolha != null && vencedora != null) ...[
            const SizedBox(height: 16),
            _Destaque(
              pick: escolha,
              verification: vencedora.state,
              confirmadoPorCrc: split.confirmed,
              // Hesita só enquanto a hesitação pode mudar alguma coisa.
              hesita: split.verifying && !split.confirmed,
              onDownload: () => onDownload(escolha),
            ),
          ] else if (split.noCertainty) ...[
            const SizedBox(height: 16),
            const _SemCerteza(),
          ] else if (faixa != null) ...[
            const SizedBox(height: 16),
            _SemFonte(reason: faixa),
          ],
          if (outras.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OutrasFontes(
              sources: outras,
              descartadas: split.discarded.length,
              comecaAberta: split.noCertainty,
              onDownload: split.noCertainty ? baixarFonte : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// O veredito de uma fonte.
///
/// Um match de tier `checksum` já nasceu de um CRC batido contra o pacote, e
/// por isso ele não passa por `verifying`: perguntar de novo seria gastar duas
/// requisições para reconfirmar o que já se sabe. Ver a "Segunda decisão
/// travada" do plano da fatia 3.
SourceVerification _estadoDe(WidgetRef ref, String gameId, MatchedSource source) {
  if (source.confidence == MatchConfidence.confirmed) return SourceVerification.crcOk;
  return verificationOf(ref.watch(sourceVerificationProvider((
    sourceId: source.sourceId,
    filename: source.filename,
    url: source.url,
    gameId: gameId,
  ))));
}

/// Qual objeto da lista de elegíveis virou a escolha.
///
/// Compara os três campos e devolve a **instância**, porque quem chama tira a
/// vencedora da lista por identidade. Duas fontes podem servir arquivos de
/// mesmo nome, e tirar as duas esconderia uma fonte real.
VerifiedSource? _vencedora(List<VerifiedSource> eligible, SourcePick? pick) {
  if (pick == null) return null;
  for (final item in eligible) {
    if (item.source.filename == pick.filename &&
        item.source.size == pick.size &&
        item.source.sourceId == pick.sourceId) {
      return item;
    }
  }
  return null;
}

/// Null quando não há o que dizer, e aí a linha fica igual à da Task 16.
String? _rotuloVerificacao(SourceVerification state) => switch (state) {
      SourceVerification.notVerified => null,
      SourceVerification.verifying => 'verificando',
      SourceVerification.crcOk => 'CRC ok',
      SourceVerification.crcDiscarded => 'descartada pelo CRC',
      SourceVerification.impossible => 'sem como verificar',
    };

String _rotuloOutras(int quantas, int descartadas) {
  final base = quantas == 1 ? 'outra fonte' : 'outras $quantas fontes';
  if (descartadas == 0) return base;
  // As descartadas estão **dentro** de [quantas]: elas desceram para a lista,
  // não sumiram (seção 8).
  return descartadas == 1 ? '$base, 1 descartada' : '$base, $descartadas descartadas';
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
  final SourceVerification verification;
  final bool confirmadoPorCrc;
  final bool hesita;
  final VoidCallback onDownload;

  const _Destaque({
    required this.pick,
    required this.verification,
    required this.confirmadoPorCrc,
    required this.hesita,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selo = _rotuloVerificacao(verification);
    final motivo = confirmadoPorCrc
        ? 'confirmado pelo CRC, é exatamente este dump'
        : pick.reason;

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
            '${formatBytes(pick.size)}, ${pick.sourceId}${selo == null ? '' : ', $selo'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(motivo, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDownload,
              child: Text(hesita ? 'Baixar mesmo assim' : 'Baixar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A faixa que substitui o card quando não há o que baixar.
///
/// O texto vem de `PickFailure.reason` na maioria dos casos, ou seja da mesma
/// regra que a folha de lote usa. A tela não inventa motivo próprio, com a
/// única exceção anotada no `build` da tela.
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

/// O card do estado "verificação impossível" da seção 8. Nunca finge certeza.
class _SemCerteza extends StatelessWidget {
  const _SemCerteza();

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'não tenho certeza de nenhuma',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Nenhuma das fontes deixou ler o CRC. Escolha uma abaixo.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A lista da seção 7, com o contador da seção 8.
class _OutrasFontes extends StatelessWidget {
  final List<VerifiedSource> sources;
  final int descartadas;
  final bool comecaAberta;

  /// Null na maioria das vezes: o botão por linha é só o estado "verificação
  /// impossível" da seção 8.
  final void Function(VerifiedSource item)? onDownload;

  const _OutrasFontes({
    required this.sources,
    required this.descartadas,
    required this.comecaAberta,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // `ExpansionTile` desenha uma divisória em cima e outra embaixo assim
      // que abre, e dentro de um `ListView` de cards isso vira duas linhas
      // soltas no meio da tela.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: comecaAberta,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          _rotuloOutras(sources.length, descartadas),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final item in sources)
            _LinhaFonte(
              item: item,
              onDownload: onDownload == null ? null : () => onDownload!(item),
            ),
        ],
      ),
    );
  }
}

class _LinhaFonte extends StatelessWidget {
  final VerifiedSource item;
  final VoidCallback? onDownload;

  const _LinhaFonte({required this.item, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selo = _rotuloVerificacao(item.state);
    final baixar = onDownload;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.source.filename, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            // Os cinco pedaços que a seção 7 pede, mais o veredito da seção 8
            // quando existe um.
            '${formatBytes(item.source.size)}, ${item.source.sourceId}, '
            '$_kTipoFonte, ${_rotuloConfianca(item.source.confidence)}'
            '${selo == null ? '' : ', $selo'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (baixar != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: baixar, child: const Text('Baixar')),
            ),
          ],
        ],
      ),
    );
  }
}

/// A confiança do **casamento**, que não é a verificação por CRC.
///
/// Ver a "Segunda decisão travada" do plano da fatia 3: são dois eixos e eles
/// não se misturam. O veredito de CRC entra na mesma linha, depois deste, como
/// um pedaço à parte.
String _rotuloConfianca(MatchConfidence confidence) => switch (confidence) {
      MatchConfidence.confirmed => 'casamento confirmado',
      MatchConfidence.likely => 'casamento provável',
      MatchConfidence.guess => 'casamento no chute',
    };
