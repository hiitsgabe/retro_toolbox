import 'dart:ui' as ui;

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

/// The hero band: cover art floating over its own blurred backdrop.
const _heroHeight = 300.0;

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
      // The app bar floats over the hero art instead of sitting on a bar of
      // its own, so the backdrop reaches the top of the screen.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(
              favorite ? Icons.favorite : Icons.favorite_border,
              color: favorite ? Colors.red : Colors.white,
            ),
            onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(key),
          ),
          Checkbox(
            value: isSelected,
            side: const BorderSide(color: Colors.white, width: 2),
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
        padding: EdgeInsets.zero,
        children: [
          _Hero(game: game, system: ref.watch(packTargetProvider)?.consoleName ?? ''),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The download affordance leads, because it is why the screen
                // was opened. In the "nothing can be verified" state neither
                // branch draws: the source list below opens instead, with a
                // button per row.
                if (choice != null && winner != null)
                  _Highlight(
                    pick: choice,
                    addonNames: addonNames,
                    verification: winner.state,
                    crcConfirmed: split.confirmed,
                    // Only hesitate while hesitating can still change something.
                    hesitating: split.verifying && !split.confirmed,
                    onDownload: () => onDownload(choice),
                  )
                else if (reason != null)
                  _NoSource(reason: reason),
                if ((game.synopsis ?? '').isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _Synopsis(text: game.synopsis!),
                ],
                if (game.shots.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _Shots(urls: game.shots),
                ],
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _OtherSources(
                    sources: others,
                    addonNames: addonNames,
                    discarded: split.discarded.length,
                    startsOpen: split.noCertainty,
                    hasHighlight: winner != null,
                    onDownload: split.noCertainty ? downloadSource : null,
                  ),
                ],
              ],
            ),
          ),
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

String _otherLabel(int count, int discarded, bool hasHighlight) {
  final base = hasHighlight
      ? (count == 1 ? 'other source' : '$count other sources')
      : (count == 1 ? 'source' : '$count sources');
  if (discarded == 0) return base;
  // The discarded ones are inside [count]: they moved down into the list,
  // they did not vanish.
  return discarded == 1 ? '$base, 1 discarded' : '$base, $discarded discarded';
}

/// The hero band: the art blurred edge to edge, the cover sharp over it, then
/// the title and the facts as chips.
class _Hero extends StatelessWidget {
  final PackGame game;
  final String system;

  const _Hero({required this.game, required this.system});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A screenshot makes a better backdrop than a cover, because it is already
    // a wide image; the cover is the fallback and the blur hides the crop.
    final backdrop = game.shots.firstOrNull ?? game.cover;

    // Genre arrives comma-separated from OpenVGDB ("Action,Shooter"), so it
    // becomes one chip per genre rather than one long chip.
    final chips = [
      if (system.isNotEmpty) system,
      if (game.year != null) '${game.year}',
      for (final genre in (game.genre ?? '').split(','))
        if (genre.trim().isNotEmpty) genre.trim(),
    ];

    final byline = [
      if ((game.developer ?? '').isNotEmpty) game.developer!,
      if ((game.publisher ?? '').isNotEmpty && game.publisher != game.developer) game.publisher!,
    ].join(' / ');

    return SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Always a dark base, art or not: the app bar icons are white and
          // have to read against whatever ends up here.
          Container(color: const Color(0xFF13161B)),
          if (backdrop != null)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: CachedNetworkImage(
                imageUrl: backdrop,
                fit: BoxFit.cover,
                errorWidget: (context, _, __) => const SizedBox.shrink(),
                errorListener: (_) {},
              ),
            ),
          // Two scrims: one darkens the whole band so white text reads, the
          // other melts the bottom edge into the page below it.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.75),
                  scheme.surface,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 104,
                  child: AspectRatio(
                    aspectRatio: 0.75,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: _cover(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (byline.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          byline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
                        ),
                      ],
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final chip in chips) _Chip(label: chip)],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final url = game.cover;
    if (url == null) {
      return Container(
        color: Colors.white.withValues(alpha: 0.08),
        child: const Icon(Icons.videogame_asset_outlined, color: Colors.white54),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (context, _, __) => Container(color: Colors.white.withValues(alpha: 0.08)),
      errorListener: (_) {},
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// The synopsis, clamped until the user asks for the rest. Several packs carry
/// paragraphs long enough to push everything else off the screen.
class _Synopsis extends StatefulWidget {
  final String text;

  const _Synopsis({required this.text});

  @override
  State<_Synopsis> createState() => _SynopsisState();
}

class _SynopsisState extends State<_Synopsis> {
  static const _clampedLines = 4;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            maxLines: _expanded ? null : _clampedLines,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
        // Always offered rather than measured: a TextPainter pass to decide
        // whether the text overflows costs more than one extra tappable word.
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _expanded ? 'Show less' : 'Read more',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The captures strip. Tapping one opens it big, because at strip size a
/// screenshot proves the game is the right one and nothing more.
/// Roughly 4:3, the shape of a console capture. The strip is a preview, not the
/// picture: the tap opens the full one.
const _shotHeight = 110.0;
const _shotWidth = 146.0;

class _Shots extends StatelessWidget {
  final List<String> urls;

  const _Shots({required this.urls});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _shotHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (context, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: InteractiveViewer(
                child: CachedNetworkImage(imageUrl: urls[i], errorListener: (_) {}),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            // An explicit width, not just a height: inside a horizontal list the
            // cross axis is bounded and the main axis is not, so without one the
            // thumbnails size themselves off the placeholder and the strip
            // collapses before the images arrive.
            child: CachedNetworkImage(
              imageUrl: urls[i],
              width: _shotWidth,
              height: _shotHeight,
              fit: BoxFit.cover,
              errorWidget: (context, _, __) => const SizedBox.shrink(),
              errorListener: (_) {},
            ),
          ),
        ),
      ),
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
          SizedBox(
            width: double.infinity,
            height: 46,
            // A plain button with its own Row, not `FilledButton.icon`: that
            // factory returns a private subclass, and `find.byType` matches the
            // exact runtime type, so every test that looks for the download
            // button would stop finding it.
            child: FilledButton(
              onPressed: onDownload,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.download_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    hesitating ? 'Download anyway' : 'Download',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            pick.filename,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '${formatBytes(pick.size)} · ${addonNames[pick.sourceId] ?? pick.sourceId}'
            '${badge == null ? '' : ' · $badge'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(reason, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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

/// The list of other sources, with the discarded counter.
class _OtherSources extends StatelessWidget {
  final List<VerifiedSource> sources;
  final Map<String, String> addonNames;
  final int discarded;
  final bool startsOpen;

  /// Whether a source above already won. With no winner these are not "other"
  /// sources, they are all of them.
  final bool hasHighlight;

  /// Null most of the time: the per-row button is only for the "verification
  /// impossible" state.
  final void Function(VerifiedSource item)? onDownload;

  const _OtherSources({
    required this.sources,
    required this.addonNames,
    required this.discarded,
    required this.startsOpen,
    required this.hasHighlight,
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
          _otherLabel(sources.length, discarded, hasHighlight),
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
    final download = onDownload;

    // Size and source, nothing else. Match confidence is how the matcher found
    // the file, which says nothing a person can act on, and the CRC verdict is
    // only worth a row of its own when it is bad news. What survives is the
    // green check, on the rows CRC actually confirmed.
    final detail = [
      formatBytes(item.source.size),
      addonNames[item.source.sourceId] ?? item.source.sourceId,
      if (item.state == SourceVerification.crcDiscarded) 'discarded by CRC',
      if (item.state == SourceVerification.verifying) 'verifying',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.state == SourceVerification.crcOk) ...[
                Icon(Icons.verified_rounded, size: 15, color: scheme.primary),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(item.source.filename, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(detail, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
