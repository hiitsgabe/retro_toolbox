import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/utils/letter_jump.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';

/// A pending L1/R1 jump: the game the views bring into view and focus. The
/// card that takes it clears it.
final gameJumpProvider = StateProvider<String?>((ref) => null);

/// L1/R1 (PageUp/PageDown) around the library's game views: jump to the first
/// game of the next or previous first letter, and flash that letter in the
/// middle of the screen for a moment. At A or Z the focused game's own letter
/// flashes and nothing moves.
class LetterJump extends ConsumerStatefulWidget {
  const LetterJump({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LetterJump> createState() => _LetterJumpState();
}

class _LetterJumpState extends ConsumerState<LetterJump> {
  String? _letter;
  int _flashes = 0;
  bool _busy = false;

  Future<void> _jump(bool forward) async {
    if (_busy) return; // a held shoulder button repeats faster than a jump resolves
    _busy = true;
    try {
      final focused = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GameCardActions>()?.game;
      final target = await ref.read(catalogProvider.notifier).letterJump(focused, forward: forward);
      // A menu or another screen opened while the list was sorting: leave it be.
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      final letter = target?.letter ?? (focused == null ? null : letterOf(focused.displayTitle));
      if (letter != null) {
        setState(() {
          _letter = letter;
          _flashes++;
        });
      }
      if (target != null) ref.read(gameJumpProvider.notifier).state = target.gameId;
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        // By letter only when the list is in name order; other sorts keep
        // DpadScope's paging. Deferred explicitly: the nearest binding wins
        // even when disabled.
        PageFocusIntent: CallbackAction<PageFocusIntent>(onInvoke: (intent) {
          if (ref.read(catalogProvider).filter.sort != CatalogSort.name) return Actions.maybeInvoke(context, intent);
          _jump(intent.forward);
          return null;
        }),
      },
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_letter != null)
            Positioned.fill(child: IgnorePointer(child: LetterFlash(key: ValueKey(_flashes), letter: _letter!))),
        ],
      ),
    );
  }
}

/// The letter a jump lands on, big in the middle of the screen: shown at once,
/// held briefly, then faded out.
class LetterFlash extends StatefulWidget {
  const LetterFlash({super.key, required this.letter});

  final String letter;

  @override
  State<LetterFlash> createState() => _LetterFlashState();
}

class _LetterFlashState extends State<LetterFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..forward();

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: FadeTransition(
        // Opaque for the first 55%, then gone.
        opacity: Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(parent: _fade, curve: const Interval(0.55, 1))),
        child: Container(
          width: 112,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: scheme.inverseSurface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(24)),
          child: Text(
            widget.letter,
            style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: scheme.onInverseSurface, height: 1),
          ),
        ),
      ),
    );
  }
}

/// A game card that a jump can land on: call [watchJump] from build and give
/// [jumpFocus] to the card's focusable widget.
mixin JumpTarget<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final jumpFocus = FocusNode();

  void watchJump(String gameId) {
    if (ref.watch(gameJumpProvider) != gameId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(gameJumpProvider) != gameId) return;
      ref.read(gameJumpProvider.notifier).state = null;
      jumpFocus.requestFocus();
      // A d-pad press back would otherwise retrace the moves made before the
      // jump (directional traversal remembers them per scope).
      final scope = jumpFocus.nearestScope;
      if (scope != null) FocusTraversalGroup.maybeOf(context)?.invalidateScopeData(scope);
      Scrollable.ensureVisible(context, alignment: 0.3, duration: const Duration(milliseconds: 120));
    });
  }

  @override
  void dispose() {
    jumpFocus.dispose();
    super.dispose();
  }
}

/// A scrolling game view that brings a jump's game near the viewport, so the
/// lazily built card exists to take it: call [listenJump] from build and give
/// [jumpScroll] to the scroll view. The first jump is an estimate from the
/// index; the next frames refine it until the card has taken the jump.
mixin JumpScroll<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final jumpScroll = ScrollController();

  void listenJump() {
    ref.listen<String?>(gameJumpProvider, (_, id) {
      if (id != null) _scrollNear(id, attempts: 4);
    });
  }

  void _scrollNear(String id, {required int attempts}) {
    final games = ref.read(catalogProvider).paginatedFilteredGames;
    final index = games.indexWhere((Game g) => g.gameId == id);
    if (index < 0) return _clearJump(id); // the list was replaced meanwhile
    if (!jumpScroll.hasClients) return;
    final position = jumpScroll.position;
    final estimate = (position.maxScrollExtent + position.viewportDimension) * index / games.length - position.viewportDimension / 3;
    position.jumpTo(estimate.clamp(0.0, position.maxScrollExtent));
    if (attempts > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(gameJumpProvider) == id) _scrollNear(id, attempts: attempts - 1);
      });
    } else {
      // Two frames on, after the card built by this last scroll had its own
      // post-frame turn: a jump still pending never lands, so it must not
      // steal focus whenever that card shows up later.
      WidgetsBinding.instance.addPostFrameCallback((_) => WidgetsBinding.instance.addPostFrameCallback((_) => _clearJump(id)));
    }
  }

  void _clearJump(String id) {
    if (mounted && ref.read(gameJumpProvider) == id) ref.read(gameJumpProvider.notifier).state = null;
  }

  @override
  void dispose() {
    jumpScroll.dispose();
    super.dispose();
  }
}
