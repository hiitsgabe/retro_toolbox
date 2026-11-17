import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_images.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/utils/image_memory.dart';

/// Builds one image of the page; [fallback] stands in while it loads and when
/// it fails.
/// [placeholder] shows while the image loads (default: [fallback]),
/// [fallback] when it fails.
typedef DetailsImageBuilder = Widget Function(BuildContext context, String url,
    {BoxFit fit, Alignment alignment, Widget? placeholder, Widget? fallback});

/// A game's details: a hero the size of the screen, then a sheet with
/// everything else. Takes its data in and renders, so the second screen can
/// host it without the page around it. Works with only what the catalog
/// knows; [launchbox] adds the rest.
class GameDetailsView extends StatelessWidget {
  const GameDetailsView({
    super.key,
    required this.game,
    this.launchbox,
    this.launchboxPending = false,
    this.actions,
    this.status,
    this.discs,
    this.sections = const [],
    this.imageBuilder,
    this.onOpenImage,
    this.scrollController,
  });

  final Game game;
  final LaunchboxGame? launchbox;

  /// [launchbox] is still being read: the logo's place is kept empty rather
  /// than showing the title and swapping it for the logo a moment later.
  final bool launchboxPending;

  /// Buttons under the title; null shows none (the second screen).
  final List<Widget>? actions;

  /// A line above [actions]: download state, an error.
  final Widget? status;

  /// A grouped multi-disc game's discs, one row each, first in the sheet.
  final Widget? discs;

  /// More parts of the sheet after [discs], (title, content), in order:
  /// versions, box set contents, extras, updates.
  final List<(String, Widget)> sections;

  /// Null: [CachedNetworkImage], with the fallback as its placeholder and
  /// error widget.
  final DetailsImageBuilder? imageBuilder;

  /// Tap on the cover, a screenshot or the back cover; null: not tappable.
  final ValueChanged<String>? onOpenImage;
  final ScrollController? scrollController;

  /// The hero's height in a viewport of [viewport]: the first screen, within
  /// reason.
  static double heroHeight(double viewport) => viewport.clamp(320.0, 720.0);

  @override
  Widget build(BuildContext context) {
    final info = _Info(game, launchbox, pending: launchboxPending);
    final image = imageBuilder ?? _networkImage;
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final gutter = width >= 1200
          ? 64.0
          : width >= 600
              ? 40.0
              : 20.0;
      return _FollowFocus(
        launchbox: launchbox,
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                info: info,
                image: image,
                height: heroHeight(box.maxHeight),
                gutter: gutter,
                narrow: width < 600,
                actions: actions,
                status: status,
                onOpenImage: onOpenImage,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 48 + MediaQuery.paddingOf(context).bottom),
              sliver: SliverList.list(children: _sheet(context, info, image, wide: width - 2 * gutter >= 1000)),
            ),
          ],
        ),
      );
    });
  }

  /// [wide]: the table and the text side by side, so a wide screen is not
  /// half empty. The screenshots stay full width under them: the d-pad goes
  /// down from the actions to whatever is below the first one, and a strip in
  /// a right-hand column would be skipped.
  List<Widget> _sheet(BuildContext context, _Info info, DetailsImageBuilder image, {required bool wide}) {
    final region = game.region;
    final shots = [
      ...launchboxImagesOf(info.images, LaunchboxImageType.screenshot, region),
      ...launchboxImagesOf(info.images, LaunchboxImageType.titleScreen, region),
    ];
    final back = pickLaunchboxImage(info.images, LaunchboxImageType.boxBack, region);
    final rows = info.rows;
    final overview = launchbox?.overview;
    final details = rows.isEmpty ? null : _Section(title: 'Details', child: _DetailsTable(rows: rows));
    final screenshots = shots.isEmpty
        ? null
        : _Section(
            title: 'Screenshots',
            child: SizedBox(
              height: _Thumb.width * 9 / 16,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _Thumb(url: shots[i].url, image: image, onOpen: onOpenImage),
              ),
            ),
          );
    final about = overview == null
        ? null
        : _Section(
            title: 'About',
            // Long lines are hard to read on a wide screen.
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: _Reading(child: Text(overview, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5))),
              ),
            ),
          );
    return [
      if (discs != null) _Section(title: 'Discs', child: discs!),
      for (final (title, child) in sections) _Section(title: title, child: child),
      if (wide && details != null && about != null) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 440, child: details),
            const SizedBox(width: 64),
            Expanded(child: about),
          ],
        ),
        if (screenshots != null) screenshots,
      ] else ...[
        if (details != null) details,
        if (screenshots != null) screenshots,
        if (about != null) about,
      ],
      if (back != null)
        _Section(
          title: 'Back of the box',
          child: Align(
            alignment: Alignment.centerLeft,
            child: _Tappable(
              url: back.url,
              onOpen: onOpenImage,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: image(context, back.url, fit: BoxFit.contain, fallback: const _Missing(height: 360)),
              ),
            ),
          ),
        ),
    ];
  }
}

/// What the page shows, from the LaunchBox record when it is there and the
/// catalog's copy of its fields when it is not (the record loads after the
/// page opens).
class _Info {
  _Info(this.game, this.lb, {this.pending = false});

  final Game game;
  final LaunchboxGame? lb;
  final bool pending;

  List<LaunchboxImage> get images => lb?.images ?? const [];

  int? get releaseDate => game.details?.releaseDate ?? game.details?.launchboxReleaseDate ?? lb?.releaseDate;
  int? get year => switch (releaseDate) { final d? when d >= 10000 => d ~/ 10000, _ => null };

  List<String> get genres => lb?.genres.isNotEmpty == true ? lb!.genres : game.details?.genres ?? const [];

  int? get maxPlayers => lb?.maxPlayers ?? game.details?.maxPlayers;
  bool? get cooperative => lb != null ? lb!.cooperative : game.details?.cooperative;

  // LaunchBox writes 0 with 0 votes for a game nobody rated.
  bool get _lbRated => lb?.rating != null && !(lb!.rating == 0 && (lb!.ratingCount ?? 0) == 0);
  double? get rating => game.details?.rating ?? (_lbRated ? lb!.rating : null);
  int? get votes => game.details?.rating != null ? game.details!.ratingCount : (_lbRated ? lb!.ratingCount : null);

  String? get players => switch (maxPlayers) {
        null || < 1 => null,
        1 => '1 player',
        final n => '1-$n players',
      };

  String get summary => [
        if (year != null) '$year',
        if (lb?.publisher != null) lb!.publisher!,
        if (genres.isNotEmpty) genres.first,
      ].join(' · ');

  List<(String, String)> get rows => [
        if (lb?.developer != null) ('Developer', lb!.developer!),
        if (lb?.publisher != null) ('Publisher', lb!.publisher!),
        if (releaseDate case final d? when d >= 10000) ('Release date', _date(d)),
        if (players != null) ('Players', players!),
        if (cooperative != null) ('Co-op', cooperative! ? 'Yes' : 'No'),
        if (lb?.esrb != null) ('ESRB', lb!.esrb!),
        if (game.region.isNotEmpty) ('Region', game.region),
        if (game.size > 0) ('Size', formatBytes(game.size)),
        if (genres.isNotEmpty) ('Genres', genres.join(', ')),
      ];

  /// yyyymmdd as yyyy-mm-dd; an unknown month or day is left off.
  static String _date(int d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final y = d ~/ 10000, m = d ~/ 100 % 100, day = d % 100;
    if (m == 0) return '$y';
    return day == 0 ? '$y-${two(m)}' : '$y-${two(m)}-${two(day)}';
  }
}

/// The first screen: background art, the logo or title, the summary, the
/// rating, the cover and the actions.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.info,
    required this.image,
    required this.height,
    required this.gutter,
    required this.narrow,
    this.actions,
    this.status,
    this.onOpenImage,
  });

  final _Info info;
  final DetailsImageBuilder image;
  final double height;
  final double gutter;
  final bool narrow;
  final List<Widget>? actions;
  final Widget? status;
  final ValueChanged<String>? onOpenImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = info.game;
    final region = game.region;
    final bg = heroBackground(info.lb, region, game.boxart);
    final front = pickLaunchboxImage(info.images, LaunchboxImageType.boxFront, region)?.url;
    final cover = front ?? game.boxart;

    // Dimmed: blown up and blurred, a cover is mostly bright flat colour.
    Widget blurred(String url) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: const BoxDecoration(color: Colors.black38),
          child: ImageFiltered(
            // clamp: decal fades the edges to transparent, a dark frame.
            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.clamp),
            child: image(context, url),
          ),
        );

    Widget? background;
    if (bg != null) {
      // Art that fails to load falls down the same chain: a screenshot after
      // the fanart, then the blurred box art.
      final boxart = game.boxart == null ? null : blurred(game.boxart!);
      final shot = pickLaunchboxImage(info.images, LaunchboxImageType.screenshot, region)?.url;
      final next = shot == null || shot == bg.url ? boxart : image(context, shot, fallback: boxart);
      // The blurred box art holds the place while the fanart loads; the
      // screenshot is only for fanart that fails. As a placeholder it would
      // load too, and the hero would go box art, screenshot, fanart.
      background = bg.blur ? blurred(bg.url) : image(context, bg.url, placeholder: boxart ?? const SizedBox.shrink(), fallback: next);
    }

    final text = _HeroText(info: info, image: image, actions: actions, status: status);
    final coverArt = cover == null
        ? null
        : _Tappable(
            url: cover,
            onOpen: onOpenImage,
            child: _Cover(
              child: image(
                context,
                cover,
                fit: BoxFit.contain,
                // A LaunchBox front that fails shows the catalog's box art.
                fallback: front != null && game.boxart != null
                    ? image(context, game.boxart!, fit: BoxFit.contain, fallback: const _Missing(height: 120))
                    : const _Missing(height: 120),
              ),
            ),
          );

    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Stack(
        alignment: AlignmentDirectional.bottomStart,
        children: [
          // The art stops short of the bottom, where the gradient is opaque:
          // at a fractional scroll offset both edges are antialiased and a
          // line of art would show through.
          Positioned.fill(bottom: 2, child: ColoredBox(color: theme.colorScheme.surface)),
          // The blur would spill onto the sheet below.
          if (background != null) Positioned.fill(bottom: 2, child: ClipRect(child: background)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Dark under the app bar too, so the back button reads on bright art.
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                    theme.scaffoldBackgroundColor.withValues(alpha: 0.75),
                    theme.scaffoldBackgroundColor,
                  ],
                  stops: const [0, 0.25, 0.7, 1],
                ),
              ),
            ),
          ),
          // Wide, the text runs over the middle of the art: shade its side.
          if (!narrow)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.scaffoldBackgroundColor.withValues(alpha: 0.7), theme.scaffoldBackgroundColor.withValues(alpha: 0)],
                    stops: const [0, 0.6],
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, top + 16, gutter, 24),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (coverArt != null) ...[coverArt, const SizedBox(height: 20)],
                      text,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: text),
                      if (coverArt != null) ...[const SizedBox(width: 32), coverArt],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText({required this.info, required this.image, this.actions, this.status});

  final _Info info;
  final DetailsImageBuilder image;
  final List<Widget>? actions;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final title = Text(
      info.game.displayTitle,
      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final logo = pickLaunchboxImage(info.images, LaunchboxImageType.clearLogo, info.game.region);
    final summary = info.summary;
    final rating = info.rating;
    final players = info.players == null ? null : [info.players!, if (info.cooperative == true) 'Co-op'].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logo == null && !info.pending && info.game.details?.launchboxId == null)
          title
        else
          // A fixed box from the first frame, the logo or the title at its
          // bottom left: nothing moves when the record or the logo comes in,
          // and the buttons below stay under a d-pad focus already placed.
          SizedBox(
            height: 96,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SizedBox.expand(
                child: logo != null
                    ? image(context, logo.url,
                        fit: BoxFit.contain, alignment: Alignment.bottomLeft, placeholder: const SizedBox.shrink(), fallback: Align(alignment: Alignment.bottomLeft, child: title))
                    : info.pending
                        ? null
                        : Align(alignment: Alignment.bottomLeft, child: title),
              ),
            ),
          ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(summary, style: theme.textTheme.titleMedium?.copyWith(color: muted)),
        ],
        if (rating != null || players != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (rating != null) ...[
                _Stars(rating: rating),
                Text(
                  info.votes == null ? rating.toStringAsFixed(1) : '${rating.toStringAsFixed(1)} (${info.votes} ${info.votes == 1 ? 'vote' : 'votes'})',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
              if (rating != null && players != null) Text('·', style: TextStyle(color: muted)),
              if (players != null) Text(players, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            ],
          ),
        ],
        if (status != null) ...[
          const SizedBox(height: 20),
          DefaultTextStyle.merge(style: theme.textTheme.bodySmall?.copyWith(color: muted), child: status!),
        ],
        if (actions != null && actions!.isNotEmpty) ...[
          SizedBox(height: status != null ? 8 : 24),
          Wrap(spacing: 12, runSpacing: 12, children: actions!),
        ],
      ],
    );
  }
}

/// Five stars filled to [rating] (0..5), in halves.
class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            switch (rating - i) {
              >= 0.75 => Icons.star_rounded,
              >= 0.25 => Icons.star_half_rounded,
              _ => Icons.star_outline_rounded,
            },
            size: 20,
            color: color,
          ),
      ],
    );
  }
}

/// The front cover: a fixed height, the width the art asks for.
class _Cover extends StatelessWidget {
  const _Cover({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(height: 120, child: child),
      ),
    );
  }
}

/// Stands in for a cover that is loading or failed: art sized by the image
/// would be zero wide, an invisible focus stop for the d-pad.
class _Missing extends StatelessWidget {
  const _Missing({required this.height, this.width});

  final double height;

  /// Null: a cover's 0.7.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width ?? height * 0.7,
      height: height,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_not_supported_outlined, size: math.min(48, height * 0.3), color: scheme.outline),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailsTable extends StatelessWidget {
  const _DetailsTable({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final value = theme.textTheme.bodyMedium;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Table(
          columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          border: TableBorder(horizontalInside: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4))),
          children: [
            for (final (l, v) in rows)
              TableRow(children: [
                Padding(padding: const EdgeInsets.fromLTRB(0, 8, 32, 8), child: Text(l, style: label)),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(v, style: value)),
              ]),
          ],
        ),
      ),
    );
  }
}

/// One 16:9 screenshot of the strip.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.image, this.onOpen});

  static const width = 180.0;

  final String url;
  final DetailsImageBuilder image;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      url: url,
      onOpen: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: SizedBox(
            width: width,
            height: width * 9 / 16,
            child: image(context, url, fallback: const _Missing(width: width, height: width * 9 / 16)),
          ),
        ),
      ),
    );
  }
}

/// [child] opens [url] on tap and is a focus stop for the d-pad, when
/// [onOpen] is given; otherwise just [child].
class _Tappable extends StatelessWidget {
  const _Tappable({required this.url, required this.onOpen, required this.child});

  final String url;
  final ValueChanged<String>? onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onOpen == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onOpen!(url),
      child: child,
    );
  }
}

const _margin = 12.0;

/// The page's vertical scroll around [context], and the scroll offsets that
/// put its box's top just under the app bar ([top]) and its bottom just above
/// the screen's edge ([bottom]). Null outside a page.
({ScrollableState scrollable, double top, double bottom})? _placeIn(BuildContext context) {
  var s = Scrollable.maybeOf(context);
  while (s != null && axisDirectionToAxis(s.axisDirection) != Axis.vertical) {
    s = Scrollable.maybeOf(s.context);
  }
  final box = context.findRenderObject();
  if (s == null || box is! RenderBox || !box.attached || !box.hasSize) return null;
  // The page's own viewport, not the screenshot strip's. Offsets come from
  // it: right after the d-pad scrolled, the box's paint position is stale.
  RenderObject? viewport = box.parent;
  while (viewport != null && !(viewport is RenderViewportBase && viewport.axis == Axis.vertical)) {
    viewport = viewport.parent;
  }
  if (viewport is! RenderViewportBase) return null;
  final clear = MediaQuery.paddingOf(context).top + kToolbarHeight + _margin;
  return (
    scrollable: s,
    top: viewport.getOffsetToReveal(box, 0).offset - clear,
    bottom: viewport.getOffsetToReveal(box, 1).offset + _margin,
  );
}

/// The overview as one d-pad stop that reads like a page: up and down scroll
/// through it a third of the screen at a time and only move on at its ends.
/// Without it a long text has nothing to focus, and the d-pad keeps
/// scrolling with focus on a control far off screen, from where it can no
/// longer find the next one.
class _Reading extends StatelessWidget {
  const _Reading({required this.child});

  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
    if (e is KeyUpEvent || (!down && e.logicalKey != LogicalKeyboardKey.arrowUp)) return KeyEventResult.ignored;
    final place = _placeIn(node.context!);
    if (place == null) return KeyEventResult.ignored;
    final position = place.scrollable.position;
    final step = position.viewportDimension / 3;
    final edge = (down ? place.bottom : place.top).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (down ? position.pixels >= edge - 0.5 : position.pixels <= edge + 0.5) return KeyEventResult.ignored;
    position.jumpTo(down ? math.min(position.pixels + step, edge) : math.max(position.pixels - step, edge));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(onKeyEvent: _onKey, child: child);
}

/// Keeps the focused control on screen and clear of the app bar the page lays
/// over the view, which the d-pad's own scrolling knows nothing about: it
/// leaves a control at the very top, under the bar, and in a hero taller than
/// the screen it can leave one below the bottom. Focus coming back into the
/// hero shows it from the top again.
class _FollowFocus extends StatefulWidget {
  const _FollowFocus({required this.launchbox, required this.child});

  /// The record arriving after focus was placed adds rows above the buttons.
  final LaunchboxGame? launchbox;
  final Widget child;

  @override
  State<_FollowFocus> createState() => _FollowFocusState();
}

class _FollowFocusState extends State<_FollowFocus> {
  bool _inHero = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_follow);
  }

  @override
  void didUpdateWidget(_FollowFocus old) {
    super.didUpdateWidget(old);
    // Only then: other rebuilds (download progress) would pull a reader
    // back to the buttons.
    if (widget.launchbox != old.launchbox) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow();
      });
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_follow);
    super.dispose();
  }

  // Runs once focus has moved, after the traversal's own ensureVisible.
  void _follow() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return;
    final place = _placeIn(ctx);
    // Focus on another page (a dialog over this one, the list below).
    if (place == null || place.scrollable.context.findAncestorStateOfType<_FollowFocusState>() != this) return;

    final hero = ctx.findAncestorWidgetOfExactType<_Hero>() != null;
    final entering = hero && !_inHero;
    _inHero = hero;
    final position = place.scrollable.position;
    var target = entering ? 0.0 : position.pixels;
    if (target < place.bottom) target = place.bottom;
    // Its top wins over its bottom when it is taller than the space.
    if (target > place.top) target = place.top;
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() > 0.5) position.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Decodes at the size it is laid out at, like the grid's covers: LaunchBox
/// fanart and screenshots are full size.
Widget _networkImage(BuildContext context, String url,
    {BoxFit fit = BoxFit.cover, Alignment alignment = Alignment.center, Widget? placeholder, Widget? fallback}) {
  return LayoutBuilder(builder: (context, box) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final w = box.hasBoundedWidth ? box.maxWidth : null;
    final h = box.hasBoundedHeight ? box.maxHeight : null;
    // Contained art is as tall as its box at most: decode by the height. The
    // box's width is the page's for the back cover and the logo.
    final byHeight = h != null && (w == null || fit == BoxFit.contain);
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 200),
      memCacheWidth: !byHeight && w != null && h != null ? thumbnailDecodeWidth(w, h, dpr) : null,
      memCacheHeight: byHeight ? math.max(1, (h * dpr).ceil()) : null,
      // The fallback also covers the load unless told otherwise: the blurred
      // box art until the fanart is in.
      placeholder: (context, url) => placeholder ?? fallback ?? const SizedBox.shrink(),
      errorWidget: (context, url, error) => fallback ?? const SizedBox.shrink(),
      errorListener: (e) => debugPrint('Details image failed: $e'),
    );
  });
}
