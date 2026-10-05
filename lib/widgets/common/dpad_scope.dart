import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/widgets/common/osk/on_screen_keyboard.dart';

/// Moves focus a page at a time (L1/R1 on handhelds map to PageUp/PageDown).
class PageFocusIntent extends Intent {
  const PageFocusIntent(this.forward);
  final bool forward;
}

/// X: mark / unmark the focused item. Screens bind it with a plain `Actions`
/// widget around the focused control; DpadScope's own no-op is the fallback.
class MarkIntent extends Intent {
  const MarkIntent();
}

/// Y: actions for the focused item.
class ItemActionsIntent extends Intent {
  const ItemActionsIntent();
}

/// Start: the screen's primary action. Falls back to activating the focused
/// control.
class PrimaryActionIntent extends Intent {
  const PrimaryActionIntent();
}

/// Select: filters / options.
class OptionsIntent extends Intent {
  const OptionsIntent();
}

/// L2/R2 (Home/End): focus the first ([end] false) or last item of the list.
class ListEdgeIntent extends Intent {
  const ListEdgeIntent(this.end);
  final bool end;
}

/// Disabled while a text field has focus, so Home/End keep moving the caret.
class _EdgeAction extends Action<ListEdgeIntent> {
  _EdgeAction(this._run);
  final void Function(bool end) _run;

  @override
  bool isEnabled(ListEdgeIntent intent) => _focusedField() == null;

  @override
  void invoke(ListEdgeIntent intent) => _run(intent.end);
}

EditableTextState? _focusedField() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();

/// Up/down: leave a text field unless it is multi-line (maxLines != 1); then
/// disabled, so the key falls through to caret movement.
class _VerticalIntent extends Intent {
  const _VerticalIntent(this.direction);
  final TraversalDirection direction;
}

class _VerticalAction extends Action<_VerticalIntent> {
  _VerticalAction(this._onMove);
  final VoidCallback _onMove;

  @override
  bool isEnabled(_VerticalIntent intent) {
    final t = _focusedField();
    return t == null || t.widget.maxLines == 1;
  }

  @override
  void invoke(_VerticalIntent intent) {
    _onMove();
    FocusManager.instance.primaryFocus?.focusInDirection(intent.direction);
  }
}

/// Left/right: leave a text field only when the caret is collapsed at that
/// edge (empty counts as both); otherwise disabled, so the key falls through
/// to normal caret movement.
class _SideIntent extends Intent {
  const _SideIntent(this.direction);
  final TraversalDirection direction;
}

class _SideAction extends Action<_SideIntent> {
  _SideAction(this._onMove);
  final VoidCallback _onMove;

  @override
  bool isEnabled(_SideIntent intent) {
    final c = _focusedField()?.widget.controller;
    if (c == null) return true;
    final sel = c.selection;
    if (!sel.isValid) return true;
    final edge = intent.direction == TraversalDirection.left ? 0 : c.text.length;
    return sel.isCollapsed && sel.baseOffset == edge;
  }

  @override
  void invoke(_SideIntent intent) {
    _onMove();
    FocusManager.instance.primaryFocus?.focusInDirection(intent.direction);
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// Enter on a single-line text field opens the on-screen keyboard (handheld
/// only; [_navigatorKey] is null when disabled). Otherwise disabled, so Enter
/// falls through to activate/submit.
class _OskIntent extends Intent {
  const _OskIntent();
}

class _OskAction extends Action<_OskIntent> {
  _OskAction(this._navigatorKey);
  final GlobalKey<NavigatorState>? _navigatorKey;

  @override
  bool isEnabled(_OskIntent intent) {
    final t = _focusedField();
    return _navigatorKey?.currentState?.overlay != null && t != null && t.widget.maxLines == 1 && !t.widget.readOnly;
  }

  @override
  void invoke(_OskIntent intent) => showOnScreenKeyboard(_navigatorKey!.currentState!.overlay!, _focusedField()!);
}

/// Global d-pad/gamepad key map plus a visible focus outline.
/// Handheld gamepads reach the app as keys: D-pad=arrows, A=Enter, B=Escape,
/// L1/R1=PageUp/PageDown, L2/R2=Home/End, X/Y/Select/Start=F2/F3/F4/F5.
class DpadScope extends StatefulWidget {
  const DpadScope({super.key, required this.child, required this.navigatorKey, this.onScreenKeyboard = false});

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Add to `MaterialApp.navigatorObservers` so focus can be kept on the top
  /// route (pages below stay in the focus tree while covered).
  static final routeObserver = TopRouteObserver();

  /// Enter on a text field opens the in-app keyboard (no platform IME).
  final bool onScreenKeyboard;

  @override
  State<DpadScope> createState() => _DpadScopeState();
}

class _DpadScopeState extends State<DpadScope> {
  static const _pageSteps = 6;

  static final _shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.arrowUp): const _VerticalIntent(TraversalDirection.up),
    const SingleActivator(LogicalKeyboardKey.arrowDown): const _VerticalIntent(TraversalDirection.down),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): const _SideIntent(TraversalDirection.left),
    const SingleActivator(LogicalKeyboardKey.arrowRight): const _SideIntent(TraversalDirection.right),
    const SingleActivator(LogicalKeyboardKey.pageUp): const PageFocusIntent(false),
    const SingleActivator(LogicalKeyboardKey.pageDown): const PageFocusIntent(true),
    const SingleActivator(LogicalKeyboardKey.escape): const _BackIntent(),
    // Android gamepads (Linux handhelds get keys from gptokeyb). Handling B
    // here stops Android from also synthesizing a system Back.
    const SingleActivator(LogicalKeyboardKey.gameButtonB): const _BackIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonLeft1): const PageFocusIntent(false),
    const SingleActivator(LogicalKeyboardKey.gameButtonRight1): const PageFocusIntent(true),
    const SingleActivator(LogicalKeyboardKey.f2): const MarkIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonX): const MarkIntent(),
    const SingleActivator(LogicalKeyboardKey.f3): const ItemActionsIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonY): const ItemActionsIntent(),
    const SingleActivator(LogicalKeyboardKey.f4): const OptionsIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonSelect): const OptionsIntent(),
    const SingleActivator(LogicalKeyboardKey.f5): const PrimaryActionIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonStart): const PrimaryActionIntent(),
    const SingleActivator(LogicalKeyboardKey.home): const ListEdgeIntent(false),
    const SingleActivator(LogicalKeyboardKey.gameButtonLeft2): const ListEdgeIntent(false),
    const SingleActivator(LogicalKeyboardKey.end): const ListEdgeIntent(true),
    const SingleActivator(LogicalKeyboardKey.gameButtonRight2): const ListEdgeIntent(true),
    const SingleActivator(LogicalKeyboardKey.enter): const _OskIntent(),
  };

  // Android gamepad A / DPAD_CENTER also open the keyboard on a text field
  // (the intent is disabled elsewhere, so they fall through to Activate).
  static final _oskShortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.gameButtonA): const _OskIntent(),
    const SingleActivator(LogicalKeyboardKey.select): const _OskIntent(),
  };

  final _repaint = _Repaint();
  Rect? _painted; // rect last drawn by the painter; the frame callback diffs against it

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_repaint.ping);
    FocusManager.instance.addHighlightModeListener(_onHighlight);
    FocusManager.instance.addListener(_hideImeOnField);
    FocusManager.instance.addListener(_keepFocusOnTopRoute);
    // Persistent callbacks can't be removed, hence the _disposed guard.
    // ponytail: runs only after frames that render anyway; repaints just when
    // the focused rect moved (scrolling), so an idle app schedules no frames.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (_disposed) return;
      if (_painted != _focusRect()) {
        _repaint.ping();
        // Persistent-callback phase: marking dirty alone schedules no frame.
        SchedulerBinding.instance.scheduleFrame();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    FocusManager.instance.removeListener(_repaint.ping);
    FocusManager.instance.removeListener(_hideImeOnField);
    FocusManager.instance.removeListener(_keepFocusOnTopRoute);
    FocusManager.instance.removeHighlightModeListener(_onHighlight);
    _repaint.dispose();
    super.dispose();
  }

  // Covered pages keep their focus nodes, so focus can end up on a page below
  // the one on screen (seen on device: the d-pad drove the hidden main menu
  // and A opened Settings). Pull it back to the top route's first control.
  void _keepFocusOnTopRoute() {
    final top = DpadScope.routeObserver.top;
    if (top is! ModalRoute) return;
    bool offTop() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null || !ctx.mounted) return false;
      final route = ModalRoute.of(ctx);
      return route != null && !route.isCurrent && !identical(route, top);
    }

    if (!offTop()) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final pageCtx = top.subtreeContext;
      if (_disposed || !offTop() || !top.isActive || pageCtx == null) return;
      final scope = FocusScope.of(pageCtx);
      final first = scope.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
      (first ?? scope).requestFocus();
    });
  }

  // Built-in keyboard on: keep the system IME down when a field takes focus
  // (best effort; the IME is asked to show after focus lands). Touch users
  // keep it: the on-screen keyboard only opens from Enter/A.
  void _hideImeOnField() {
    if (!widget.onScreenKeyboard || FocusManager.instance.highlightMode == FocusHighlightMode.touch) return;
    if (_focusedField() == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  // A held activate key must act once. The default Enter/A/Select/Space ->
  // ActivateIntent shortcuts also match key repeats, so swallow the repeats
  // here (above them). Text fields keep their own repeats unless the built-in
  // keyboard owns typing.
  static final _activateKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.select,
  };

  // Button intents never repeat, even in a text field.
  static final _buttonKeys = {
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.gameButtonX,
    LogicalKeyboardKey.gameButtonY,
    LogicalKeyboardKey.gameButtonSelect,
    LogicalKeyboardKey.gameButtonStart,
  };

  KeyEventResult _swallowRepeat(FocusNode _, KeyEvent e) {
    if (e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_buttonKeys.contains(e.logicalKey)) return KeyEventResult.handled;
    if (!_activateKeys.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (!widget.onScreenKeyboard && _focusedField() != null) return KeyEventResult.ignored;
    return KeyEventResult.handled;
  }

  void _onHighlight(FocusHighlightMode _) => _repaint.ping();

  Rect? _focusRect() {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return null;
    }
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (node == null || node is FocusScopeNode || ctx is! Element) return null;
    // Elements replaced during layout stay deactivated until the frame ends;
    // findRenderObject() asserts on them (release builds fall to `attached`).
    if (kDebugMode && !ctx.debugIsActive) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return node.rect;
  }

  // Not DismissIntent: a page route registers a disabled DismissIntent action
  // that would shadow ours. Dialogs/sheets keep handling Escape themselves.
  void _back() {
    _edgeRun++;
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null && ModalRoute.of(ctx) is PopupRoute) {
      Actions.maybeInvoke(ctx, const DismissIntent());
    } else {
      widget.navigatorKey.currentState?.maybePop();
    }
  }

  /// One focus step; false when focus did not move.
  bool _step(TraversalDirection dir) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !node.focusInDirection(dir)) return false;
    // Focus changes are otherwise applied in a microtask, after the caller's loop.
    FocusManager.instance.applyFocusChangesIfNeeded();
    return FocusManager.instance.primaryFocus != node;
  }

  // Lazy lists only build near the viewport: wait a frame between steps so
  // ensureVisible's scroll builds the next items.
  // Any newer edge run or focus-moving intent bumps [_edgeRun]; older runs exit.
  int _edgeRun = 0;

  static ScrollableState? _scrollable(FocusNode? n) {
    final ctx = n?.context;
    return ctx == null ? null : Scrollable.maybeOf(ctx);
  }

  // Stays inside the scrollable that held focus when pressed: a step that lands
  // outside it (or goes nowhere) is undone. A failed step may only mean the
  // next item is not built yet, so it is retried once after a frame.
  Future<void> _listEdge(bool end) async {
    final token = ++_edgeRun;
    final dir = end ? TraversalDirection.down : TraversalDirection.up;
    final home = _scrollable(FocusManager.instance.primaryFocus);
    FocusNode? stuck;
    while (!_disposed && token == _edgeRun) {
      for (var i = 0; i < 10; i++) {
        final prev = FocusManager.instance.primaryFocus;
        if (prev == null) return;
        if (_step(dir) && _scrollable(FocusManager.instance.primaryFocus) == home) {
          stuck = null;
          continue;
        }
        if (FocusManager.instance.primaryFocus != prev) {
          prev.requestFocus();
          FocusManager.instance.applyFocusChangesIfNeeded();
        }
        if (identical(stuck, prev)) return;
        stuck = prev;
        break;
      }
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  void _pageFocus(bool forward) {
    _edgeRun++;
    final dir = forward ? TraversalDirection.down : TraversalDirection.up;
    var moved = false;
    for (var i = 0; i < _pageSteps && _step(dir); i++) {
      moved = true;
    }
    // Nothing to focus (text-only view): keep the stock page scroll.
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (!moved && ctx != null) {
      Actions.maybeInvoke(
        ctx,
        ScrollIntent(direction: forward ? AxisDirection.down : AxisDirection.up, type: ScrollIncrementType.page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Shortcuts(
      shortcuts: {..._shortcuts, if (widget.onScreenKeyboard) ..._oskShortcuts},
      // Below Shortcuts so repeats are dropped before our own Start shortcut.
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _swallowRepeat,
        child: Actions(
          actions: {
            PageFocusIntent: CallbackAction<PageFocusIntent>(
              onInvoke: (i) => _pageFocus(i.forward),
            ),
            _VerticalIntent: _VerticalAction(() => _edgeRun++),
            _SideIntent: _SideAction(() => _edgeRun++),
            _BackIntent: CallbackAction<_BackIntent>(
              onInvoke: (_) => _back(),
            ),
            // Fallbacks: a screen's own Actions around the focused widget win.
            PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(
              onInvoke: (_) {
                final ctx = FocusManager.instance.primaryFocus?.context;
                return ctx == null ? null : Actions.maybeInvoke(ctx, const ActivateIntent());
              },
            ),
            MarkIntent: DoNothingAction(),
            ItemActionsIntent: DoNothingAction(),
            OptionsIntent: DoNothingAction(),
            ListEdgeIntent: _EdgeAction(_listEdge),
            _OskIntent: _OskAction(widget.onScreenKeyboard ? widget.navigatorKey : null),
          },
          child: Stack(
            textDirection: TextDirection.ltr,
            fit: StackFit.passthrough,
            children: [
              widget.child,
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('dpad-focus-outline'),
                      painter: _OutlinePainter(this, color, _repaint),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this._state, this._color, Listenable repaint) : super(repaint: repaint);

  final _DpadScopeState _state;
  final Color _color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _state._painted = _state._focusRect();
    if (rect == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _color,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old._color != _color;
}

/// Tracks the top route of the app's navigator for [DpadScope].
class TopRouteObserver extends NavigatorObserver {
  final _stack = <Route<dynamic>>[];
  Route<dynamic>? get top => _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute == null) return;
    if (i < 0) {
      _stack.add(newRoute);
    } else {
      _stack[i] = newRoute;
    }
  }
}
