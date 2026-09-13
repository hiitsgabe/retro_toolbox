import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/utils/formatters.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';

/// The source type, which in this slice is only one. A constant rather than a
/// loose literal for the day it becomes a field.
const _kSourceKind = 'HTTP';

/// One game, its sources, the reason for the pick and what CRC verification said
/// about each. A route, not a bottom sheet or an inline expansion.
class GameDetailScreen extends ConsumerWidget {
  final PackGridEntry entry;

  /// What to do when the user presses Download. The screen does not know the
  /// queue, for the same reason `PackGrid` does not know `Navigator`:
  /// `HomeScreen` wires the two together.
  final void Function(SourcePick pick) onDownload;

  /// What to do when the user presses Download on the footer bar, which is the
  /// batch and not this game. A callback for the same reason as [onDownload].
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
    final key = entry.selectionKey;
    final favorite = ref.watch(favoritesProvider).isFavorite(key);
    final selected = ref.watch(catalogProvider.select((s) => s.selectedGames));
    final isSelected = selected.contains(key);
    final resolver = ref.watch(gameResolverProvider);
    final addonNames = ref.watch(addonNamesProvider);

    // The verdicts are resolved here, once, and passed down as data. The child
    // widgets never see `ref`. The per-source `watch` is cheap because the
    // Riverpod family caches by (source, file).
    final verified = <VerifiedSource>[
      for (final source in entry.sources) (source: source, state: _stateOf(ref, game.id, source)),
    ];
    final split = splitByVerification(verified);

    // The same batch rule, with a single entry, over what survived
    // verification. One rule, two places.
    final plan = planFromEntries(
      [PackGridEntry(game: game, sources: [for (final v in split.eligible) v.source])],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: resolver,
      sourcePriority: ref.watch(sourcePriorityProvider),
    );

    final choice = split.noCertainty ? null : plan.picks.firstOrNull;
    final winner = _winner(split.eligible, choice);
    final others = [
      for (final v in verified)
        if (!identical(v.source, winner?.source)) v,
    ];

    // The only string on this screen that does not come from `PickFailure`, and
    // it has to be: the batch does not verify CRC, so the batch rule does not
    // know this state. Do not "fix" it by moving the string to the service.
    final reason = split.eligible.isEmpty && split.discarded.isNotEmpty
        ? 'no source passed CRC verification'
        : (split.noCertainty ? null : plan.failures.firstOrNull?.reason);

    void downloadSource(VerifiedSource item) {
      final game_ = resolver(item.source);
      if (game_ == null) return;
      onDownload(SourcePick(
        gameId: key,
        title: game.title,
        filename: item.source.filename,
        size: item.source.size,
        sourceId: item.source.sourceId,
        reason: 'chosen by you, no verification possible',
        uncertain: true,
        game: game_,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(game.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(
              favorite ? Icons.favorite : Icons.favorite_border,
              color: favorite ? Colors.red : null,
            ),
            onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(key),
          ),
          Checkbox(
            value: isSelected,
            onChanged: (_) => ref.read(catalogProvider.notifier).toggleGameSelection(key),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SelectionBar(
        // `pack: true` literal, not read from `gridModeProvider`: this screen
        // only exists in PACK MODE, because only `PackGrid` pushes it.
        count: selectionKeysFor(selected, pack: true).length,
        onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
        onDownload: onBatchDownload,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Top(game: game, system: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (choice != null && winner != null) ...[
            const SizedBox(height: 16),
            _Highlight(
              pick: choice,
              addonNames: addonNames,
              verification: winner.state,
              crcConfirmed: split.confirmed,
              // Only hesitate while hesitating can still change something.
              hesitating: split.verifying && !split.confirmed,
              onDownload: () => onDownload(choice),
            ),
          ] else if (split.noCertainty) ...[
            const SizedBox(height: 16),
            const _NoCertainty(),
          ] else if (reason != null) ...[
            const SizedBox(height: 16),
            _NoSource(reason: reason),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OtherSources(
              sources: others,
              addonNames: addonNames,
              discarded: split.discarded.length,
              startsOpen: split.noCertainty,
              onDownload: split.noCertainty ? downloadSource : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// The verdict for a source. A `checksum`-tier match was already born from a CRC
/// checked against the pack, so it never passes through `verifying`.
SourceVerification _stateOf(WidgetRef ref, String gameId, MatchedSource source) {
  if (source.confidence == MatchConfidence.confirmed) return SourceVerification.crcOk;
  return verificationOf(ref.watch(sourceVerificationProvider((
    sourceId: source.sourceId,
    filename: source.filename,
    url: source.url,
    gameId: gameId,
  ))));
}

/// Which object in the eligible list became the pick. Compares the three fields
/// and returns the instance, because the caller removes the winner from the
/// list by identity, and two sources can serve files of the same name.
VerifiedSource? _winner(List<VerifiedSource> eligible, SourcePick? pick) {
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

/// Null when there is nothing to say, and then the line matches the plain one.
String? _verificationLabel(SourceVerification state) => switch (state) {
      SourceVerification.notVerified => null,
      SourceVerification.verifying => 'verifying',
      SourceVerification.crcOk => 'CRC ok',
      SourceVerification.crcDiscarded => 'discarded by CRC',
      SourceVerification.impossible => 'cannot verify',
    };

String _otherLabel(int count, int discarded) {
  final base = count == 1 ? 'other source' : '$count other sources';
  if (discarded == 0) return base;
  // The discarded ones are inside [count]: they moved down into the list,
  // they did not vanish.
  return discarded == 1 ? '$base, 1 discarded' : '$base, $discarded discarded';
}

class _Top extends StatelessWidget {
  final PackGame game;
  final String system;

  const _Top({required this.game, required this.system});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Only what exists joins the line, else a game with no year or publisher
    // (most homebrews) leaves a dangling comma.
    final details = [
      system,
      if (game.year != null) '${game.year}',
      if ((game.publisher ?? '').isNotEmpty) game.publisher!,
      if ((game.genre ?? '').isNotEmpty) game.genre!,
    ].where((part) => part.isNotEmpty).join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _cover(context),
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
              Text(details, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cover(BuildContext context) {
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

/// The card for the chosen version. The reason is the line that cannot be
/// missing.
class _Highlight extends StatelessWidget {
  final SourcePick pick;

  /// Addon id to name. Empty is a legitimate state: whoever is not in the map is
  /// drawn by id.
  final Map<String, String> addonNames;
  final SourceVerification verification;
  final bool crcConfirmed;
  final bool hesitating;
  final VoidCallback onDownload;

  const _Highlight({
    required this.pick,
    required this.addonNames,
    required this.verification,
    required this.crcConfirmed,
    required this.hesitating,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _verificationLabel(verification);
    final reason = crcConfirmed
        ? 'confirmed by CRC, this is exactly the dump'
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
                _kSourceKind,
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
            '${formatBytes(pick.size)}, ${addonNames[pick.sourceId] ?? pick.sourceId}'
            '${badge == null ? '' : ', $badge'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(reason, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDownload,
              child: Text(hesitating ? 'Download anyway' : 'Download'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The banner that replaces the card when there is nothing to download. The
/// text comes from `PickFailure.reason` in most cases, i.e. the same rule the
/// batch sheet uses, with the single exception noted in the screen's `build`.
class _NoSource extends StatelessWidget {
  final String reason;

  const _NoSource({required this.reason});

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

/// The card for the "verification impossible" state. It never fakes certainty.
class _NoCertainty extends StatelessWidget {
  const _NoCertainty();

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
            'not sure about any of them',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'None of the sources let the CRC be read. Pick one below.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The list of other sources, with the discarded counter.
class _OtherSources extends StatelessWidget {
  final List<VerifiedSource> sources;
  final Map<String, String> addonNames;
  final int discarded;
  final bool startsOpen;

  /// Null most of the time: the per-row button is only for the "verification
  /// impossible" state.
  final void Function(VerifiedSource item)? onDownload;

  const _OtherSources({
    required this.sources,
    required this.addonNames,
    required this.discarded,
    required this.startsOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // `ExpansionTile` draws a divider above and below once it opens, which
      // inside a `ListView` of cards becomes two stray lines mid-screen.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: startsOpen,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          _otherLabel(sources.length, discarded),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final item in sources)
            _SourceRow(
              item: item,
              addonNames: addonNames,
              onDownload: onDownload == null ? null : () => onDownload!(item),
            ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final VerifiedSource item;
  final Map<String, String> addonNames;
  final VoidCallback? onDownload;

  const _SourceRow({required this.item, required this.addonNames, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _verificationLabel(item.state);
    final download = onDownload;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.source.filename, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            // The five pieces, plus the verification verdict when there is one.
            '${formatBytes(item.source.size)}, '
            '${addonNames[item.source.sourceId] ?? item.source.sourceId}, '
            '$_kSourceKind, ${_confidenceLabel(item.source.confidence)}'
            '${badge == null ? '' : ', $badge'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (download != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: download, child: const Text('Download')),
            ),
          ],
        ],
      ),
    );
  }
}

/// The match confidence, which is not the CRC verification. Two axes that never
/// mix; the CRC verdict joins the same line, after this, as a separate piece.
String _confidenceLabel(MatchConfidence confidence) => switch (confidence) {
      MatchConfidence.confirmed => 'confirmed match',
      MatchConfidence.likely => 'likely match',
      MatchConfidence.guess => 'guessed match',
    };
