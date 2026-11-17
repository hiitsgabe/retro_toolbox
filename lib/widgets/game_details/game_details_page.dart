import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/services/disc_sets.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_view.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/utils/formatters.dart';

const _labels = {
  GameAction.download: 'Download',
  GameAction.pause: 'Pause',
  GameAction.resume: 'Resume',
  GameAction.cancel: 'Cancel',
  GameAction.extract: 'Extract',
  GameAction.retryDownload: 'Retry download',
  GameAction.retryExtraction: 'Retry extraction',
};

const _icons = {
  GameAction.download: Icons.download_rounded,
  GameAction.pause: Icons.pause_rounded,
  GameAction.resume: Icons.play_arrow_rounded,
  GameAction.cancel: Icons.close_rounded,
  GameAction.extract: Icons.unarchive_outlined,
  GameAction.retryDownload: Icons.refresh_rounded,
  GameAction.retryExtraction: Icons.refresh_rounded,
};

/// A game's page: its details plus everything the card can do, as buttons.
/// Actions run with the page's own ref and context (the card may unmount
/// while the page is open) and the page closes once they finish. Back is
/// ignored while an action runs (closing would dispose the ref mid-action
/// and drop it).
class GameDetailsPage extends ConsumerStatefulWidget {
  const GameDetailsPage({super.key, required this.game, this.selectable = true});

  final Game game;
  final bool selectable;

  /// Test seam: images without the network or the image cache plugin.
  @visibleForTesting
  static DetailsImageBuilder? debugImageBuilder;

  @override
  ConsumerState<GameDetailsPage> createState() => _GameDetailsPageState();
}

class _GameDetailsPageState extends ConsumerState<GameDetailsPage> {
  LaunchboxGame? _launchbox;
  bool _lookingUp = false;
  bool _busy = false;
  final _scroll = ScrollController();

  /// The hero has scrolled away: the app bar gets a background and the title,
  /// or the sheet would scroll under a bare back button.
  final _pastHero = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final media = MediaQuery.of(context);
      final bar = media.padding.top + kToolbarHeight;
      _pastHero.value = _scroll.offset > GameDetailsView.heroHeight(media.size.height) - bar;
    });
    // The catalog only carries the fields lists sort and filter on; the
    // rest is read from the platform file now, while the page already shows.
    final details = widget.game.details;
    final platform = details?.launchboxPlatform;
    final id = details?.launchboxId;
    if (platform != null && id != null) {
      _lookingUp = true;
      ref.read(launchboxServiceProvider).lookup(platform, id).then((lb) {
        if (!mounted) return;
        setState(() {
          _launchbox = lb;
          _lookingUp = false;
        });
      }, onError: (Object e) {
        debugPrint('LaunchBox lookup failed: $e');
        if (mounted) setState(() => _lookingUp = false);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pastHero.dispose();
    super.dispose();
  }

  Future<void> _run(GameState gameState, GameAction action) async {
    setState(() => _busy = true);
    try {
      await runGameAction(ref, context, widget.game, gameState, action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final gameState = ref.watch(gameStateProvider(game));
    final isFavorite = ref.watch(favoritesProvider).isFavorite(game.gameId);
    final isSelected = ref.watch(gameSelectionProvider(game.gameId));
    final actions = [
      for (final a in gameState.availableActions)
        if (_labels.containsKey(a)) a,
    ];

    // All one button type, unkeyed: when Select goes away the next button
    // takes over its element, and with it the focus.
    Widget button(String label, IconData icon, VoidCallback onPressed, {bool primary = false, bool autofocus = false}) => primary
        ? FilledButton.icon(autofocus: autofocus, onPressed: onPressed, icon: Icon(icon), label: Text(label))
        : FilledButton.tonalIcon(autofocus: autofocus, onPressed: onPressed, icon: Icon(icon), label: Text(label));

    final error = gameState.errorMessage;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: ValueListenableBuilder<bool>(
            valueListenable: _pastHero,
            builder: (context, past, _) => AppBar(
              // Not a focus stop: once the focused control scrolls off the top,
              // Down would land on it and the rest of the page is unreachable.
              // B and touch still go back.
              leading: const ExcludeFocus(child: BackButton()),
              backgroundColor: past ? Theme.of(context).scaffoldBackgroundColor : null,
              title: past ? Text(game.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
            ),
          ),
        ),
        body: GameDetailsView(
          game: game,
          launchbox: _launchbox,
          launchboxPending: _lookingUp,
          scrollController: _scroll,
          imageBuilder: GameDetailsPage.debugImageBuilder,
          onOpenImage: (url) => showImageViewer(context, url),
          status: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(gameState.statusText),
              if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
          discs: game.discs.length >= 2 ? GameDiscList(discs: game.discs) : null,
          actions: [
            for (final a in actions) button(_labels[a]!, _icons[a]!, () => _run(gameState, a), primary: a == actions.first, autofocus: a == actions.first),
            button(
              isFavorite ? 'Remove from favourites' : 'Add to favourites',
              isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              () => ref.read(favoritesProvider.notifier).toggleFavorite(game.gameId),
              autofocus: actions.isEmpty,
            ),
            if (widget.selectable && (gameState.isInteractable || isSelected))
              button(
                isSelected ? 'Unselect' : 'Select',
                isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                () => ref.read(catalogProvider.notifier).toggleGameSelection(game.gameId),
              ),
            if (game.boxart != null) button('View box art', Icons.image_outlined, () => showBoxartViewer(context, game)),
          ],
        ),
      ),
    );
  }
}

/// One row per disc of a grouped game: its number, size and state, and the
/// one thing it can do now. Each runs for that disc alone and the page stays.
class GameDiscList extends StatelessWidget {
  const GameDiscList({super.key, required this.discs});

  final List<Game> discs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, disc) in discs.indexed) _DiscRow(disc: disc, number: discNumber(disc) == 0 ? i + 1 : discNumber(disc)),
      ],
    );
  }
}

class _DiscRow extends ConsumerWidget {
  const _DiscRow({required this.disc, required this.number});

  final Game disc;
  final int number;

  static const _order = [
    GameAction.download,
    GameAction.pause,
    GameAction.resume,
    GameAction.cancel,
    GameAction.extract,
    GameAction.retryDownload,
    GameAction.retryExtraction,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(disc));
    final action = _order.where(state.availableActions.contains).firstOrNull;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text('Disc $number', style: const TextStyle(fontWeight: FontWeight.w600))),
          SizedBox(width: 88, child: Text(formatBytes(disc.size), style: TextStyle(color: muted))),
          Expanded(child: Text(state.statusText, style: TextStyle(color: muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (action != null)
            FilledButton.tonalIcon(
              onPressed: () => runGameAction(ref, context, disc, state, action),
              icon: Icon(_icons[action]),
              label: Text(_labels[action]!),
            ),
        ],
      ),
    );
  }
}
