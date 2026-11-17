import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';

/// Gamepad buttons for a focused game card: X marks it (where the checkbox
/// would work), Y opens its page, holding A opens its box art.
class GameCardActions extends ConsumerWidget {
  const GameCardActions({super.key, required this.game, required this.selectable, required this.child});

  final Game game;
  final bool selectable;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Actions(
      actions: {
        MarkIntent: CallbackAction<MarkIntent>(onInvoke: (_) {
          if (selectable && (ref.read(gameStateProvider(game)).isInteractable || ref.read(gameSelectionProvider(game.gameId)))) {
            ref.read(catalogProvider.notifier).toggleGameSelection(game.gameId);
          }
          return null;
        }),
        ItemActionsIntent: CallbackAction<ItemActionsIntent>(
          onInvoke: (_) => showGameActionMenu(context, game, selectable: selectable),
        ),
      },
      child: game.boxart == null ? child : _HoldForBoxart(game: game, child: child),
    );
  }
}

/// Test seam for the hold-A box art viewer.
@visibleForTesting
void Function(BuildContext context, Game game)? debugShowBoxart;

/// Holding A (Enter) on a card opens its box art; a short press still
/// activates the card, on release.
class _HoldForBoxart extends StatefulWidget {
  const _HoldForBoxart({required this.game, required this.child});

  final Game game;
  final Widget child;

  @override
  State<_HoldForBoxart> createState() => _HoldForBoxartState();
}

class _HoldForBoxartState extends State<_HoldForBoxart> {
  static const _hold = Duration(milliseconds: 500);
  static final _keys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.select,
  };

  Timer? _timer;
  bool _down = false; // pressed here (not, say, the A that closed a dialog)

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (!_keys.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _down = true;
      _timer = Timer(_hold, () {
        _timer = null;
        if (mounted) (debugShowBoxart ?? showBoxartViewer)(context, widget.game);
      });
    } else if (e is KeyUpEvent) {
      if (!_down) return KeyEventResult.ignored;
      _down = false;
      if (_timer != null) {
        _timer!.cancel();
        _timer = null;
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
      }
    }
    return KeyEventResult.handled; // repeats too
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: widget.child);
}

/// The page a card opens: the game's details, with everything the row's
/// small buttons and checkbox do as buttons.
Future<void> showGameActionMenu(BuildContext context, Game game, {bool selectable = true}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => GameDetailsPage(game: game, selectable: selectable)),
  );
}
