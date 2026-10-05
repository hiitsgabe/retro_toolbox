import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/widgets/common/osk/osk_controller.dart';

/// Docks the on-screen keyboard at the bottom of [overlay], typing into
/// [field]. While open it owns the d-pad: arrows move between keys, A types,
/// B hides (Android: gameButtonB), Y = backspace, X = space, L1/R1 = caret. At most one is open;
/// it closes itself when the field leaves the tree or its route stops being
/// the top one.
void showOnScreenKeyboard(OverlayState overlay, EditableTextState field) {
  _close();
  // A d-pad can't make selections; a select-all left by focus would make the
  // first key replace the whole text.
  final v = field.textEditingValue;
  if (!v.selection.isValid || !v.selection.isCollapsed) {
    field.userUpdateTextEditingValue(
      v.copyWith(selection: TextSelection.collapsed(offset: v.text.length)),
      SelectionChangedCause.keyboard,
    );
  }
  // Android: keep Gboard from opening over the built-in keyboard.
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  late final OverlayEntry entry;
  final route = ModalRoute.of(field.context);
  entry = _open = OverlayEntry(
    // A stale keyboard's close must not take down a newer one.
    builder: (_) => _Osk(field: field, route: route, onClose: () => identical(_open, entry) ? _close() : null),
  );
  overlay.insert(entry);
}

OverlayEntry? _open;

/// Idempotent; every exit goes through here.
void _close() {
  final e = _open;
  _open = null;
  e
    ?..remove()
    ..dispose();
}

class _Osk extends StatefulWidget {
  const _Osk({required this.field, required this.route, required this.onClose});

  final EditableTextState field;
  final ModalRoute<Object?>? route;
  final VoidCallback onClose;

  @override
  State<_Osk> createState() => _OskState();
}

class _OskState extends State<_Osk> {
  static const _c = OskController(); // maxLength: the field's own formatter enforces it
  static const _letters = ['1234567890', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  static const _symbols = [r'1234567890', r'!@#$%^&*()_', r'-+=/\|:;' "'" r'"?', r'.,<>[]{}~`'];

  final _scope = FocusScopeNode(debugLabel: 'osk');
  bool _shift = false;
  bool _symbolPage = false;

  EditableTextState get _field => widget.field;
  FocusNode get _fieldNode => _field.widget.focusNode;
  bool get _signed => _field.widget.keyboardType.signed ?? false;
  bool get _numeric => _field.widget.keyboardType.index == TextInputType.number.index;

  /// The field's screen is still up: field mounted, its route on top.
  bool get _alive => _field.mounted && (widget.route?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _watch();
  }

  // ponytail: checked after every rendered frame; a pop or a rebuild that
  // drops the field always renders one, and an idle app runs nothing.
  void _watch() => SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_alive) return widget.onClose();
        _watch();
      });

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  void _edit(TextEditingValue Function(TextEditingValue) f) {
    if (!_alive) return widget.onClose();
    final now = _field.textEditingValue;
    final next = f(now);
    // An unchanged value makes EditableText grab focus back.
    if (next != now) _field.userUpdateTextEditingValue(next, SelectionChangedCause.keyboard);
    if (mounted) setState(() {});
  }

  void _type(String s) {
    _edit((v) => _c.insert(v, s));
    if (_shift && mounted) setState(() => _shift = false); // one-shot
  }

  void _backspace() => _edit(_c.backspace);
  void _caret(int d) => _edit((v) => _c.moveCaret(v, d));

  void _hide() {
    final alive = _alive;
    widget.onClose();
    if (alive) _fieldNode.requestFocus();
  }

  void _done() {
    if (!_alive) return widget.onClose();
    final node = _fieldNode;
    _field.performAction(_field.widget.textInputAction ?? TextInputAction.done);
    FocusManager.instance.applyFocusChangesIfNeeded();
    // e.g. TextInputAction.next, or the handler pushed/popped a route.
    final moved = !_scope.hasFocus || !_alive;
    widget.onClose();
    if (!moved) node.nextFocus();
  }

  void _arrow(TraversalDirection d) => FocusManager.instance.primaryFocus?.focusInDirection(d);

  Widget _key(String id, String label, VoidCallback onTap, {int flex = 2, bool autofocus = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: autofocus,
            focusColor: Colors.transparent, // the DpadScope outline is the only indicator
            onTap: onTap,
            child: Center(
              child: Text(label, key: ValueKey('osk-$id'), style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _chars(String row, {bool first = false}) => [
        for (final (i, ch) in row.split('').indexed)
          _key(ch, _shift ? ch.toUpperCase() : ch, () => _type(_shift ? ch.toUpperCase() : ch), autofocus: first && i == 0),
      ];

  List<Widget> _rows() {
    if (_numeric) {
      return [
        Row(children: _chars('123', first: true)),
        Row(children: _chars('456')),
        Row(children: _chars('789')),
        Row(children: [
          if (_signed) _key('-', '-', () => _type('-')),
          _key('.', '.', () => _type('.')),
          _key('0', '0', () => _type('0')),
          _key('backspace', '⌫', _backspace, flex: 2),
        ]),
        Row(children: [_key('left', '◀', () => _caret(-1)), _key('Done', 'Done', _done), _key('right', '▶', () => _caret(1))]),
      ];
    }
    final page = _symbolPage ? _symbols : _letters;
    return [
      Row(children: _chars(page[0])),
      Row(children: _chars(page[1], first: true)),
      Row(children: [if (!_symbolPage) const Spacer(), ..._chars(page[2]), if (!_symbolPage) const Spacer()]),
      Row(children: [
        if (!_symbolPage) _key('shift', _shift ? '⇧ on' : '⇧', () => setState(() => _shift = !_shift), flex: 3),
        ..._chars(page[3]),
        _key('backspace', '⌫', _backspace, flex: 3),
      ]),
      Row(children: [
        _key('symbols', _symbolPage ? 'ABC' : '?123', () => setState(() => _symbolPage = !_symbolPage), flex: 3),
        _key('left', '◀', () => _caret(-1)),
        _key('space', 'space', () => _type(' '), flex: 6),
        _key('right', '▶', () => _caret(1)),
        _key('.', '.', () => _type('.')),
        _key('Done', 'Done', _done, flex: 5),
      ]),
    ];
  }

  Widget _header(ColorScheme scheme) {
    final v = _field.mounted ? _field.textEditingValue : TextEditingValue.empty;
    final text = _field.mounted && _field.widget.obscureText ? '•' * v.text.length : v.text;
    final caret = (v.selection.isValid ? v.selection.extentOffset : text.length).clamp(0, text.length);
    return SizedBox(
      height: 24,
      // ponytail: reverse keeps the end of long text in view; a caret far left
      // of a long text can scroll out of sight.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Text.rich(
          key: const ValueKey('osk-header'),
          TextSpan(children: [
            TextSpan(text: text.substring(0, caret)),
            TextSpan(text: '▏', style: TextStyle(color: scheme.primary)),
            TextSpan(text: text.substring(caret)),
          ]),
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.sizeOf(context).height * 0.45,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _arrow(TraversalDirection.up),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _arrow(TraversalDirection.down),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _arrow(TraversalDirection.left),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _arrow(TraversalDirection.right),
          const SingleActivator(LogicalKeyboardKey.escape): _hide,
          const SingleActivator(LogicalKeyboardKey.tab): _backspace,
          const SingleActivator(LogicalKeyboardKey.space): () => _numeric ? null : _type(' '),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _caret(-1),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _caret(1),
          // Android gamepad buttons.
          const SingleActivator(LogicalKeyboardKey.gameButtonB): _hide,
          const SingleActivator(LogicalKeyboardKey.gameButtonY): _backspace,
          const SingleActivator(LogicalKeyboardKey.gameButtonX): () => _numeric ? null : _type(' '),
          const SingleActivator(LogicalKeyboardKey.gameButtonLeft1): () => _caret(-1),
          const SingleActivator(LogicalKeyboardKey.gameButtonRight1): () => _caret(1),
        },
        child: FocusScope(
          node: _scope,
          child: Material(
            key: const ValueKey('osk'),
            color: scheme.surfaceContainerHigh,
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Column(children: [
                _header(scheme),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: _numeric ? 360 : double.infinity),
                      child: Column(children: [for (final r in rows) Expanded(child: r)]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
