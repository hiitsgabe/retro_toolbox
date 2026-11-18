import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/widgets/game_list/letter_jump.dart';

/// How a card style lays out the game list: [count] cards built by [card].
/// [onNearEnd] loads more, for layouts that page by focus instead of scroll
/// (null when nothing is left to load). [controller] goes on the one scroll
/// view that holds the cards: an L1/R1 jump scrolls it near a card not built yet.
typedef StyledGameLayout = Widget Function(
  BuildContext context,
  int count,
  Widget Function(BuildContext context, int index) card,
  VoidCallback? onNearEnd,
  ScrollController controller,
);

/// The catalog's games for a card style: [layout] lays out the cards that
/// [card] builds; scrolling near the end on either axis loads more, as GameGrid does.
class StyledGameList extends ConsumerStatefulWidget {
  const StyledGameList({super.key, required this.card, required this.layout});

  /// The style's card for [game], usually a StyledGameCard; [autofocus] is set
  /// for the first.
  final Widget Function(BuildContext context, Game game, {required bool autofocus}) card;
  final StyledGameLayout layout;

  @override
  ConsumerState<StyledGameList> createState() => _StyledGameListState();
}

class _StyledGameListState extends ConsumerState<StyledGameList> with JumpScroll<StyledGameList> {
  static const _loadMoreThresholdPx = 500.0;

  @override
  Widget build(BuildContext context) {
    final games = ref.watch(catalogProvider.select((s) => s.paginatedFilteredGames));
    final hasMore = ref.watch(catalogProvider.select((s) => s.hasMoreItems));
    listenJump();

    void loadMore() {
      final s = ref.read(catalogProvider);
      if (s.hasMoreItems && !s.loadingMore) ref.read(catalogProvider.notifier).loadMoreItems();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Either axis: some styles scroll sideways.
        if (n is ScrollUpdateNotification && n.metrics.pixels >= n.metrics.maxScrollExtent - _loadMoreThresholdPx) loadMore();
        return false;
      },
      child: widget.layout(
        context,
        games.length,
        (c, i) => KeyedSubtree(key: ValueKey(games[i].gameId), child: widget.card(c, games[i], autofocus: i == 0)),
        hasMore ? loadMore : null,
        jumpScroll,
      ),
    );
  }
}
