import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/widgets/launcher/launch_flow.dart';

/// Gamepad buttons for a focused game card: X marks it (where the checkbox
/// would work), Y opens its page, holding A opens its box art. Focus here also
/// tells the second screen which game to show, except on a Task Manager row
/// ([selectable] false): the games screen is still up under the sheet, and the
/// row's game may be from another console.
class GameCardActions extends ConsumerStatefulWidget {
  const GameCardActions({super.key, required this.game, required this.selectable, required this.child});

  final Game game;
  final bool selectable;
  final Widget child;

  @override
  ConsumerState<GameCardActions> createState() => _GameCardActionsState();
}

class _GameCardActionsState extends ConsumerState<GameCardActions> {
  final _focus = FocusNode(canRequestFocus: false, skipTraversal: true);

  void _report() {
    if (widget.selectable) ref.read(focusedGameProvider.notifier).state = widget.game;
  }

  // Cover flow keeps its one focus stop and swaps the centre game under it,
  // so focus never moves: the new game has to be reported here.
  @override
  void didUpdateWidget(GameCardActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Under touch the flow has no focus, but its old centre may be the game
    // the second screen shows: the new centre takes its place there too.
    if (oldWidget.game.gameId != widget.game.gameId && (_focus.hasFocus || _wasShown(oldWidget.game))) {
      Future.microtask(() {
        if (mounted) _report();
      });
    }
  }

  bool _wasShown(Game old) => widget.selectable && ref.read(dualScreenProvider).companionOpen && ref.read(focusedGameProvider)?.gameId == old.gameId;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game, selectable = widget.selectable, child = widget.child;
    final actions = Actions(
      actions: {
        MarkIntent: CallbackAction<MarkIntent>(onInvoke: (_) {
          if (selectable) toggleCardSelection(ref, game);
          return null;
        }),
        ItemActionsIntent: CallbackAction<ItemActionsIntent>(
          onInvoke: (_) => showGameActionMenu(context, game, selectable: selectable),
        ),
      },
      child: game.boxart == null ? child : _HoldForBoxart(game: game, child: child),
    );
    return Focus(
      focusNode: _focus,
      onFocusChange: (focused) {
        if (focused) _report();
      },
      child: actions,
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

/// A tap on a game card (or A). With the second screen open, a game it does
/// not show yet is shown there (and takes the focus here); a tap on the game
/// it shows selects it, since its page, discs and updates included, is
/// already on the second screen, or in launcher mode launches it when it
/// would launch. Y still opens the page here. [focus]: the card's focus stop.
void tapGameCard(BuildContext context, WidgetRef ref, Game game, {bool selectable = true, FocusNode? focus}) {
  if (selectable && ref.read(dualScreenProvider).companionOpen) {
    if (ref.read(focusedGameProvider)?.gameId != game.gameId) {
      ref.read(focusedGameProvider.notifier).state = game;
      focus?.requestFocus();
    } else if (_mayLaunch(ProviderScope.containerOf(context, listen: false), game)) {
      _launchOr(context, game, () => toggleCardSelection(ref, game));
    } else {
      toggleCardSelection(ref, game);
    }
    return;
  }
  activateGame(context, game, selectable: selectable);
}

/// Test seam: what a card's launch runs instead of the emulator.
@visibleForTesting
Future<void> Function(BuildContext context, Game game, LaunchChoice choice)? debugLaunchGame;

/// A card activated: a tap, A, or Start with nothing selected. In launcher
/// mode a game on disk launches with the emulator Play would pick (its
/// override, its console's default, the one covering emulator); anything
/// else opens its page, at once and exactly as with the mode off. A Task
/// Manager row ([selectable] false) only ever opens its page: its game may
/// be another console's.
Future<void> activateGame(BuildContext context, Game game, {bool selectable = true}) {
  if (!selectable || !_mayLaunch(ProviderScope.containerOf(context, listen: false), game)) {
    return showGameActionMenu(context, game, selectable: selectable);
  }
  return _launchOr(context, game, () => showGameActionMenu(context, game));
}

/// Launcher mode is on and [game] is on disk: a catalog game downloaded or
/// extracted, or a loose game, which is on disk by construction.
bool _mayLaunch(ProviderContainer c, Game game) {
  if (!c.read(launcherModeProvider)) return false;
  final status = c.read(gameStateProvider(game)).status;
  return game.isLocal || status == GameStatus.downloaded || status == GameStatus.extracted;
}

/// Launches [game] with its resolved choice, or runs [otherwise] when it has
/// none. The session and the saved overrides come first: the one covering
/// emulator is only known from the session, and nothing may have read the
/// overrides yet.
Future<void> _launchOr(BuildContext context, Game game, void Function() otherwise) async {
  final c = ProviderScope.containerOf(context, listen: false);
  await c.read(launcherSessionProvider.future);
  await c.read(launchOverridesProvider.notifier).loaded;
  if (!context.mounted) return;
  final choice = c.read(resolveChoiceProvider(game));
  if (choice == null) return otherwise();
  // As the page does on open: the second screen shows the game launched.
  c.read(focusedGameProvider.notifier).state = game;
  await (debugLaunchGame ?? (context, game, choice) => LaunchFlow(context, game).launch(choice))(context, game, choice);
}

/// X on a card: selects or unselects it, unless it is busy and not selected.
void toggleCardSelection(WidgetRef ref, Game game) {
  if (ref.read(gameStateProvider(game)).isInteractable || ref.read(gameSelectionProvider(game.gameId))) {
    ref.read(catalogProvider.notifier).toggleGameSelection(game.gameId);
  }
}

/// Outlines the card whose game the second screen shows, in the style's
/// focus colour. The d-pad outline is hidden after a touch; this one is not.
class SecondScreenHighlight extends StatelessWidget {
  const SecondScreenHighlight({super.key, required this.shown, required this.child, this.radius = 0});

  final bool shown;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Always the same box, so the card under it is not rebuilt from scratch.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: shown
          ? BoxDecoration(
              border: Border.all(color: StyleTokens.of(context).focus.color, width: 2),
              borderRadius: BorderRadius.circular(radius),
            )
          : const BoxDecoration(),
      child: child,
    );
  }
}

/// The details page's route name: the games screen still counts as up under it.
const gameDetailsRouteName = 'game-details';

/// The page a card opens: the game's details, with everything the row's
/// small buttons and checkbox do as buttons.
Future<void> showGameActionMenu(BuildContext context, Game game, {bool selectable = true}) {
  // A tap opens the page without moving focus to the card.
  if (selectable) ProviderScope.containerOf(context, listen: false).read(focusedGameProvider.notifier).state = game;
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: const RouteSettings(name: gameDetailsRouteName),
      builder: (_) => GameDetailsPage(game: game, selectable: selectable),
    ),
  );
}
