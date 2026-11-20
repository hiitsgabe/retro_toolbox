import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/menu_order_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// How a style shows the tile being moved.
enum LiftLook {
  /// Up off the row, with a shadow (Classic, Switch).
  raised,

  /// Larger than its neighbours (3DS).
  scaled,

  /// Rocking in place (Vita).
  wobble,

  /// Ringed in the style's accent (Wii).
  outline,
}

enum _Move { row, list, grid, columns, vita }

/// Where an arrow takes the moving tile in one layout: the index math of the
/// layout it is in. Left and right step through reading order everywhere.
class MenuMove {
  /// One row: left and right.
  const MenuMove.row() : _kind = _Move.row, _n = 1;

  /// One column (a list, a cover flow): every arrow steps one place.
  const MenuMove.list() : _kind = _Move.list, _n = 1;

  /// Rows of [columns], filled row by row.
  const MenuMove.grid(int columns) : _kind = _Move.grid, _n = columns;

  /// Columns of [rows], filled column by column, scrolling sideways (3DS).
  const MenuMove.columns(int rows) : _kind = _Move.columns, _n = rows;

  /// Vita rows: [wide] places, then one fewer half a place in, in turn.
  const MenuMove.vita(int wide) : _kind = _Move.vita, _n = wide;

  final _Move _kind;
  final int _n;

  /// The index the tile at [from] of [count] goes to on [d]; null when it
  /// stays (an edge).
  int? target(int from, TraversalDirection d, int count) {
    int? step(int to) => to >= 0 && to < count ? to : null;
    final back = d == TraversalDirection.left || d == TraversalDirection.up;
    final along = d == TraversalDirection.left || d == TraversalDirection.right;
    switch (_kind) {
      case _Move.row:
        return along ? step(from + (back ? -1 : 1)) : null;
      case _Move.list:
        return step(from + (back ? -1 : 1));
      case _Move.grid:
        if (along) return step(from + (back ? -1 : 1));
        return _across(from, back ? -_n : _n, count);
      case _Move.columns:
        if (!along) return step(from + (back ? -1 : 1));
        return _across(from, back ? -_n : _n, count);
      case _Move.vita:
        if (along) return step(from + (back ? -1 : 1));
        return _vita(from, back ? -1 : 1, count);
    }
  }

  /// [by] whole lines (rows of a grid, columns of the 3DS shelf): the last
  /// tile when the next line is a short one.
  int? _across(int from, int by, int count) {
    final to = from + by;
    if (to < 0) return null;
    if (to < count) return to;
    return from ~/ _n.abs() < (count - 1) ~/ _n.abs() ? count - 1 : null;
  }

  int? _vita(int from, int by, int count) {
    final wide = math.max(2, _n), pair = 2 * wide - 1;
    int start(int row) => row ~/ 2 * pair + (row.isOdd ? wide : 0);
    final row = from ~/ pair * 2 + (from % pair >= wide ? 1 : 0);
    final next = row + by;
    if (next < 0 || start(next) >= count) return null;
    final place = math.min(from - start(row), (next.isOdd ? wide - 1 : wide) - 1);
    return math.min(start(next) + place, count - 1);
  }
}

/// The layout under it, for the tiles moving in it.
class MenuMoveLayout extends InheritedWidget {
  const MenuMoveLayout({super.key, required this.move, required super.child});

  final MenuMove move;

  static MenuMove of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MenuMoveLayout>()?.move ?? const MenuMove.list();

  @override
  bool updateShouldNotify(MenuMoveLayout old) => old.move._kind != move._kind || old.move._n != move._n;
}

/// One menu's move mode: which tile is lifted and where it is now. The
/// order is saved only on a drop.
class MenuReorder extends ChangeNotifier {
  MenuReorder({required this.onDrop});

  /// The ids on screen after a drop that changed the order (the Tasks tile left out).
  final void Function(List<String> ids) onDrop;

  static const hold = Duration(milliseconds: 500);
  static final _a = {LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.select};
  static final _b = {LogicalKeyboardKey.escape, LogicalKeyboardKey.gameButtonB};
  static final _arrows = {
    LogicalKeyboardKey.arrowLeft: TraversalDirection.left,
    LogicalKeyboardKey.arrowRight: TraversalDirection.right,
    LogicalKeyboardKey.arrowUp: TraversalDirection.up,
    LogicalKeyboardKey.arrowDown: TraversalDirection.down,
  };

  List<MenuTile> _base = const [];
  Map<String, MenuTile> _byId = const {};
  List<String>? _order;
  String? _lifted;
  bool _touch = false;
  Axis? _steps;
  double _stepped = 0;

  /// A pressed here, its hold timer running.
  String? _held;
  Timer? _timer;

  /// The tile to take focus back once rebuilt where it now is.
  String? refocus;

  final _targets = <String, State>{};

  /// The tiles, the lifted one where it is now.
  List<MenuTile> get tiles => _order == null ? _base : [for (final id in _order!) _byId[id]!];

  bool get moving => _lifted != null;

  /// Lifted by a long press (a finger moves it, its release drops it).
  bool get touch => moving && _touch;

  String? get lifted => _lifted;

  int? get liftedIndex => _lifted == null ? null : _order!.indexOf(_lifted!);

  /// The lifted tile's index, or once put down the index of the tile last
  /// lifted: where a view showing one tile at a time (a cover flow) stays.
  int? get moverIndex {
    if (_lifted != null) return liftedIndex;
    final last = _last;
    if (last == null) return null;
    final i = _base.indexWhere((t) => t.id == last);
    return i < 0 ? null : i;
  }

  String? _last;

  bool isLifted(String id) => id == _lifted;

  /// The menu's tiles, in their saved order; a move under way ends when the
  /// tiles themselves change.
  void update(List<MenuTile> base) {
    final same = base.length == _base.length && [for (var i = 0; i < base.length; i++) base[i].id == _base[i].id].every((b) => b);
    _base = base;
    _byId = {for (final t in base) t.id: t};
    _unique = _byId.length == base.length;
    if (!same && moving) {
      _order = null;
      _lifted = null;
    }
  }

  /// The Tasks tile stays first.
  int get _floor => _base.isNotEmpty && _base.first.id == MenuTile.tasksId ? 1 : 0;

  bool _unique = true;

  bool movable(String id) => _unique && id != MenuTile.tasksId && _byId.containsKey(id) && _base.length - _floor > 1;

  /// Picks up [id]. [steps]: a finger dragging along that axis moves it one
  /// place a step (a cover flow, where the cards slide under the finger).
  void lift(String id, {bool touch = false, Axis? steps}) {
    if (moving || !movable(id)) return;
    _cancelHold();
    _order = [for (final t in _base) t.id];
    _lifted = id;
    _touch = touch;
    _steps = steps;
    _stepped = 0;
    if (touch) HapticFeedback.mediumImpact();
    notifyListeners();
  }

  /// The lifted tile to [index] (never ahead of the Tasks tile).
  void moveTo(int index) {
    final from = liftedIndex;
    if (from == null) return;
    final to = index.clamp(_floor, _order!.length - 1);
    if (to == from) return;
    _order!
      ..removeAt(from)
      ..insert(to, _lifted!);
    if (!_touch && _targets.containsKey(_lifted)) refocus = _lifted;
    notifyListeners();
  }

  /// The lifted tile one arrow [d] along [layout].
  void step(TraversalDirection d, MenuMove layout) {
    final from = liftedIndex;
    if (from == null) return;
    final to = layout.target(from, d, _order!.length);
    if (to != null) moveTo(to);
  }

  /// Puts the lifted tile down where it is; the order is saved when it changed.
  void drop() {
    final ids = _order;
    if (ids == null) return;
    final changed = [for (var i = 0; i < ids.length; i++) ids[i] != _base[i].id].any((b) => b);
    _end();
    if (changed) onDrop([for (final id in ids) if (id != MenuTile.tasksId) id]);
    notifyListeners();
  }

  /// Puts the lifted tile back where it was.
  void cancel() {
    if (!moving) return;
    _end();
    notifyListeners();
  }

  void _end() {
    if (!_touch && _targets.containsKey(_lifted)) refocus = _lifted;
    _last = _lifted;
    _order = null;
    _lifted = null;
    _held = null;
  }

  void _cancelHold() {
    _timer?.cancel();
    _timer = null;
  }

  /// A key on tile [id] (or on any tile while one is lifted): hold A to
  /// lift, a short A still runs the tile (on release); while lifted the
  /// arrows move it along [layout], A drops and B cancels.
  KeyEventResult handleKey(String id, KeyEvent e, MenuMove layout) {
    final key = e.logicalKey;
    if (moving) {
      if (e is KeyUpEvent) {
        if (_a.contains(key) && _held != null) {
          _held = null;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      final d = _arrows[key];
      if (d != null) {
        step(d, layout);
      } else if (e is KeyDownEvent && _a.contains(key)) {
        drop();
      } else if (e is KeyDownEvent && _b.contains(key)) {
        cancel();
      }
      // Nothing else leaves the menu mid-move.
      return KeyEventResult.handled;
    }
    if (!_a.contains(key)) {
      if (e is KeyDownEvent && _held != null) {
        _cancelHold();
        _held = null;
      }
      return KeyEventResult.ignored;
    }
    if (!movable(id)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _held = id;
      _cancelHold();
      _timer = Timer(hold, () {
        _timer = null;
        if (_held == id) {
          lift(id);
          _held = id; // its release is still to come
        }
      });
    } else if (e is KeyUpEvent) {
      if (_held != id) return KeyEventResult.ignored;
      _held = null;
      if (_timer != null) {
        _cancelHold();
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
      }
    }
    return KeyEventResult.handled; // repeats too
  }

  /// A finger at [global] while a long press holds the lifted tile.
  void dragTo(Offset global, Offset delta) {
    if (!touch) return;
    if (_steps case final axis?) {
      _stepped += axis == Axis.horizontal ? delta.dx : delta.dy;
      const stride = 64.0;
      while (_stepped.abs() >= stride) {
        final forward = _stepped > 0;
        _stepped -= forward ? stride : -stride;
        step(forward ? TraversalDirection.right : TraversalDirection.left, const MenuMove.list());
      }
      return;
    }
    for (final MapEntry(key: id, value: state) in _targets.entries) {
      if (id == _lifted || !state.mounted) continue;
      final box = state.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      if ((Offset.zero & box.size).contains(box.globalToLocal(global))) {
        moveTo(_order!.indexOf(id));
        return;
      }
    }
  }

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }
}

/// Puts a [MenuReorder] over a menu's tiles.
class MenuReorderScope extends InheritedNotifier<MenuReorder> {
  const MenuReorderScope({super.key, required MenuReorder super.notifier, required super.child});

  static MenuReorder? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MenuReorderScope>()?.notifier;
}

/// A menu whose tiles can be moved: [tiles] in their saved order under
/// [menuId], [builder] laying them out (the lifted one where it is now). A
/// finger that lifted a tile drags it; the pad's hint row shows mid-move.
class ReorderableMenu extends ConsumerStatefulWidget {
  const ReorderableMenu({super.key, required this.menuId, required this.tiles, required this.builder});

  final String menuId;
  final List<MenuTile> tiles;
  final Widget Function(BuildContext context, List<MenuTile> tiles) builder;

  /// [tiles] in the [saved] order, the Tasks tile first.
  static List<MenuTile> ordered(List<MenuTile> tiles, List<String>? saved) {
    // Two tiles of one id cannot be told apart in a saved order.
    if (tiles.map((t) => t.id).toSet().length != tiles.length) return tiles;
    final byId = {for (final t in tiles) t.id: t};
    final rest = [for (final t in tiles) if (t.id != MenuTile.tasksId) t.id];
    return [
      if (byId[MenuTile.tasksId] case final tasks?) tasks,
      for (final id in applyMenuOrder(rest, saved)) byId[id]!,
    ];
  }

  @override
  ConsumerState<ReorderableMenu> createState() => _ReorderableMenuState();
}

class _ReorderableMenuState extends ConsumerState<ReorderableMenu> {
  late final _reorder = MenuReorder(onDrop: (ids) => ref.read(menuOrderProvider.notifier).save(widget.menuId, ids));

  /// The hint in the title row: always up, empty unless a tile is lifted.
  final _titleRow = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleRow.show();
    });
  }

  @override
  void dispose() {
    _reorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(menuOrderProvider.select((m) => m[widget.menuId]));
    _reorder.update(ReorderableMenu.ordered(widget.tiles, saved));
    final gamepad = ref.watch(inputModeProvider) == InputMode.gamepad;
    return MenuReorderScope(
      notifier: _reorder,
      child: Builder(builder: (context) {
        final r = MenuReorderScope.of(context)!;
        return PopScope(
          canPop: !r.moving,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) r.cancel();
          },
          child: Listener(
            onPointerMove: (e) => r.dragTo(e.position, e.delta),
            onPointerUp: (_) {
              if (r.touch) r.drop();
            },
            onPointerCancel: (_) {
              if (r.touch) r.cancel();
            },
            // The hint keeps clear of the tiles: in the title row's right
            // side on a landscape screen, under the menu on a phone, where
            // the menu leaves room.
            child: OverlayPortal(
              controller: _titleRow,
              overlayChildBuilder: (context) {
                final r = MenuReorderScope.of(context)!;
                if (!r.moving || !gamepad || MediaQuery.orientationOf(context) != Orientation.landscape) return const SizedBox.shrink();
                return Positioned(
                  top: MediaQuery.paddingOf(context).top,
                  right: 12,
                  height: kToolbarHeight,
                  child: const Center(child: MenuMoveHint()),
                );
              },
              child: Stack(children: [
                widget.builder(context, r.tiles),
                if (r.moving && gamepad && MediaQuery.orientationOf(context) == Orientation.portrait)
                  const Positioned(left: 0, right: 0, bottom: 10, child: Center(child: MenuMoveHint())),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

/// "◀▶ move · A drop · B cancel", while a tile is lifted.
class MenuMoveHint extends StatelessWidget {
  const MenuMoveHint({super.key});

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final style = t.subtitle.copyWith(color: t.ink.withValues(alpha: 0.85));
    Widget dot() => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('·', style: style));
    return DecoratedBox(
      key: const ValueKey('menu-move-hint'),
      decoration: BoxDecoration(
        // Opaque: a label under it must not show through.
        color: Color.alphaBlend(Colors.black.withValues(alpha: 0.45), t.k.surface.withValues(alpha: 1)),
        borderRadius: BorderRadius.circular(t.k.buttonRadius + 6),
        border: Border.all(color: t.k.panelLine),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('◀▶ move', style: style),
          dot(),
          const PadKey(PadButton.a),
          const SizedBox(width: 5),
          Text('drop', style: style),
          dot(),
          const PadKey(PadButton.b),
          const SizedBox(width: 5),
          Text('cancel', style: style),
        ]),
      ),
    );
  }
}

/// A tile of a [ReorderableMenu]: holding A on it (or a long press) lifts
/// it, and it shows [look] while lifted. Outside a [ReorderableMenu], just
/// [child]. [color]: the outline's (the style's accent when null); [radius]:
/// the outline's and the shadow's corners.
class MenuReorderTarget extends StatefulWidget {
  MenuReorderTarget({required this.tile, required this.look, required this.child, this.color, this.radius = 16}) : super(key: MenuTileKey(tile.id));

  final MenuTile tile;
  final LiftLook look;
  final Color? color;
  final double radius;
  final Widget child;

  @override
  State<MenuReorderTarget> createState() => _MenuReorderTargetState();
}

/// A [MenuReorderTarget]'s key: its tile's id, so the tile keeps its state
/// when it moves, and the tile's own key (its label) stays free for the card.
class MenuTileKey extends LocalKey {
  const MenuTileKey(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is MenuTileKey && other.id == id;

  @override
  int get hashCode => Object.hash(MenuTileKey, id);

  @override
  String toString() => 'MenuTileKey($id)';
}

class _MenuReorderTargetState extends State<MenuReorderTarget> {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);
  MenuReorder? _reorder;

  String get _id => widget.tile.id;

  @override
  void didUpdateWidget(MenuReorderTarget old) {
    super.didUpdateWidget(old);
    if (old.tile.id != _id && _reorder?._targets[old.tile.id] == this) _reorder!._targets.remove(old.tile.id);
  }

  @override
  void dispose() {
    if (_reorder?._targets[_id] == this) _reorder!._targets.remove(_id);
    _node.dispose();
    super.dispose();
  }

  void _refocus() {
    final r = _reorder;
    if (!mounted || r == null || r.refocus != _id) return;
    r.refocus = null;
    final stop = _node.descendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
    if (stop != null && !stop.hasPrimaryFocus) stop.requestFocus();
    Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
  }

  @override
  Widget build(BuildContext context) {
    final r = MenuReorderScope.of(context);
    if (r == null) return widget.child;
    if (_reorder != r) {
      if (_reorder?._targets[_id] == this) _reorder!._targets.remove(_id);
      _reorder = r;
    }
    r._targets[_id] = this;
    if (r.refocus == _id) WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
    final move = MenuMoveLayout.of(context);
    return Focus(
      focusNode: _node,
      onKeyEvent: (_, e) => r.handleKey(_id, e, move),
      child: GestureDetector(
        onLongPressStart: r.movable(_id) ? (_) => r.lift(_id, touch: true) : null,
        child: MenuLiftLook(lifted: r.isLifted(_id), look: widget.look, color: widget.color, radius: widget.radius, child: widget.child),
      ),
    );
  }
}

/// [child] as [look] draws a lifted tile, while [lifted]. The same widgets
/// either way, so the tile under it keeps its state (and focus).
class MenuLiftLook extends StatefulWidget {
  const MenuLiftLook({super.key, required this.lifted, required this.look, required this.child, this.color, this.radius = 16});

  final bool lifted;
  final LiftLook look;
  final Color? color;
  final double radius;
  final Widget child;

  @override
  State<MenuLiftLook> createState() => _MenuLiftLookState();
}

class _MenuLiftLookState extends State<MenuLiftLook> with TickerProviderStateMixin {
  late final _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 160), value: widget.lifted ? 1 : 0);
  AnimationController? _wobble;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MenuLiftLook old) {
    super.didUpdateWidget(old);
    if (old.lifted != widget.lifted || old.look != widget.look) _sync();
  }

  void _sync() {
    widget.lifted ? _lift.forward() : _lift.reverse();
    if (widget.lifted && widget.look == LiftLook.wobble) {
      (_wobble ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 420))).repeat();
    } else {
      _wobble?.stop();
      _wobble?.value = 0;
    }
  }

  @override
  void dispose() {
    _lift.dispose();
    _wobble?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? StyleTokens.of(context).accent;
    return AnimatedBuilder(
      animation: _wobble == null ? _lift : Listenable.merge([_lift, _wobble]),
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_lift.value);
        final look = widget.look;
        final scale = 1 + t * switch (look) { LiftLook.scaled => 0.16, LiftLook.raised => 0.05, LiftLook.wobble => 0.06, LiftLook.outline => 0.03 };
        final rise = look == LiftLook.raised ? t * 12 : 0.0;
        final angle = look == LiftLook.wobble ? math.sin((_wobble?.value ?? 0) * 2 * math.pi) * 0.05 * t : 0.0;
        final radius = BorderRadius.circular(widget.radius);
        return Transform.translate(
          offset: Offset(0, -rise),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: DecoratedBox(
                key: const ValueKey('menu-lift-look'),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    if (t > 0 && look != LiftLook.outline)
                      BoxShadow(color: Colors.black.withValues(alpha: 0.45 * t), blurRadius: 22 * t, offset: Offset(0, 6 + rise)),
                    if (t > 0 && look == LiftLook.outline) BoxShadow(color: accent.withValues(alpha: 0.55 * t), blurRadius: 18 * t, spreadRadius: 2 * t),
                  ],
                ),
                position: DecorationPosition.background,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: look == LiftLook.outline && t > 0 ? Border.all(color: accent.withValues(alpha: t), width: 4) : null,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
