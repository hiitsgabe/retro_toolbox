import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Moves focus a page at a time (L1/R1 on handhelds map to PageUp/PageDown).
class PageFocusIntent extends Intent {
  const PageFocusIntent(this.forward);
  final bool forward;
}

/// Left/right: leave a text field only when the caret is collapsed at that
/// edge (empty counts as both); otherwise disabled, so the key falls through
/// to normal caret movement.
class _SideIntent extends Intent {
  const _SideIntent(this.direction);
  final TraversalDirection direction;
}

class _SideAction extends Action<_SideIntent> {
  @override
  bool isEnabled(_SideIntent intent) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    final c = ctx?.findAncestorStateOfType<EditableTextState>()?.widget.controller;
    if (c == null) return true;
    final sel = c.selection;
    if (!sel.isValid) return true;
    final edge = intent.direction == TraversalDirection.left ? 0 : c.text.length;
    return sel.isCollapsed && sel.baseOffset == edge;
  }

  @override
  void invoke(_SideIntent intent) {
    FocusManager.instance.primaryFocus?.focusInDirection(intent.direction);
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// Global d-pad/gamepad key map plus a visible focus outline.
/// Handheld gamepads reach the app as keys: D-pad=arrows, A=Enter, B=Escape,
/// L1/R1=PageUp/PageDown.
class DpadScope extends StatefulWidget {
  const DpadScope({super.key, required this.child, required this.navigatorKey});

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<DpadScope> createState() => _DpadScopeState();
}

class _DpadScopeState extends State<DpadScope> {
  static const _pageSteps = 6;

  static final _shortcuts = <ShortcutActivator, Intent>{
    for (final (key, dir) in [
      (LogicalKeyboardKey.arrowUp, TraversalDirection.up),
      (LogicalKeyboardKey.arrowDown, TraversalDirection.down),
    ])
      SingleActivator(key): DirectionalFocusIntent(dir, ignoreTextFields: false),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): const _SideIntent(TraversalDirection.left),
    const SingleActivator(LogicalKeyboardKey.arrowRight): const _SideIntent(TraversalDirection.right),
    const SingleActivator(LogicalKeyboardKey.pageUp): const PageFocusIntent(false),
    const SingleActivator(LogicalKeyboardKey.pageDown): const PageFocusIntent(true),
    const SingleActivator(LogicalKeyboardKey.escape): const _BackIntent(),
  };

  final _repaint = _Repaint();
  Rect? _painted; // rect last drawn by the painter; the frame callback diffs against it

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_repaint.ping);
    FocusManager.instance.addHighlightModeListener(_onHighlight);
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
    FocusManager.instance.removeHighlightModeListener(_onHighlight);
    _repaint.dispose();
    super.dispose();
  }

  void _onHighlight(FocusHighlightMode _) => _repaint.ping();

  Rect? _focusRect() {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return null;
    }
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode || node.context == null) {
      return null;
    }
    final box = node.context!.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return node.rect;
  }

  // Not DismissIntent: a page route registers a disabled DismissIntent action
  // that would shadow ours. Dialogs/sheets keep handling Escape themselves.
  void _back() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null && ModalRoute.of(ctx) is PopupRoute) {
      Actions.maybeInvoke(ctx, const DismissIntent());
    } else {
      widget.navigatorKey.currentState?.maybePop();
    }
  }

  void _pageFocus(bool forward) {
    final dir = forward ? TraversalDirection.down : TraversalDirection.up;
    for (var i = 0; i < _pageSteps; i++) {
      final node = FocusManager.instance.primaryFocus;
      if (node == null || !node.focusInDirection(dir)) break;
      // Focus changes are otherwise applied in a microtask, after this loop.
      FocusManager.instance.applyFocusChangesIfNeeded();
      if (FocusManager.instance.primaryFocus == node) break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: {
          PageFocusIntent: CallbackAction<PageFocusIntent>(
            onInvoke: (i) => _pageFocus(i.forward),
          ),
          _SideIntent: _SideAction(),
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) => _back(),
          ),
        },
        child: Stack(
          textDirection: TextDirection.ltr,
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('dpad-focus-outline'),
                  painter: _OutlinePainter(this, color, _repaint),
                ),
              ),
            ),
          ],
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
