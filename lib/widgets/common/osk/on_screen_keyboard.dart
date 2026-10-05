import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/widgets/common/osk/osk_controller.dart';

/// Docks the on-screen keyboard at the bottom of [overlay], typing into
/// [field]. While open it owns the d-pad: arrows move between keys, A types,
/// B hides, Y = backspace, X = space, L1/R1 = caret.
void showOnScreenKeyboard(OverlayState overlay, EditableTextState field) {
  // A d-pad can't make selections; a select-all left by focus would make the
  // first key replace the whole text.
  final v = field.textEditingValue;
  if (!v.selection.isValid || !v.selection.isCollapsed) {
    field.userUpdateTextEditingValue(
      v.copyWith(selection: TextSelection.collapsed(offset: v.text.length)),
      SelectionChangedCause.keyboard,
    );
  }
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Osk(field: field, onClose: () => entry
      ..remove()
      ..dispose()),
  );
  overlay.insert(entry);
}

class _Osk extends StatefulWidget {
  const _Osk({required this.field, required this.onClose});

  final EditableTextState field;
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
  bool get _numeric => _field.widget.keyboardType.index == TextInputType.number.index;

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  void _edit(TextEditingValue Function(TextEditingValue) f) {
    if (!_field.mounted) return widget.onClose();
    final now = _field.textEditingValue;
    final next = f(now);
    // An unchanged value makes EditableText grab focus back.
    if (next != now) _field.userUpdateTextEditingValue(next, SelectionChangedCause.keyboard);
    if (mounted) setState(() {});
  }

  void _type(String s) {
    _edit((v) => _c.insert(v, s));
    if (_shift) setState(() => _shift = false); // one-shot
  }

  void _backspace() => _edit(_c.backspace);
  void _caret(int d) => _edit((v) => _c.moveCaret(v, d));

  void _hide() {
    final node = _fieldNode;
    widget.onClose();
    node.requestFocus();
  }

  void _done() {
    final node = _fieldNode;
    _field.performAction(_field.widget.textInputAction ?? TextInputAction.done);
    FocusManager.instance.applyFocusChangesIfNeeded();
    final moved = !_scope.hasFocus; // e.g. TextInputAction.next, or a pushed route
    widget.onClose();
    if (!moved && node.context != null) node.nextFocus();
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
    final back = _key('backspace', '⌫', _backspace, flex: 3);
    if (_numeric) {
      return [
        Row(children: _chars('123', first: true)),
        Row(children: _chars('456')),
        Row(children: _chars('789')),
        Row(children: [_key('.', '.', () => _type('.')), _key('0', '0', () => _type('0')), _key('backspace', '⌫', _backspace, flex: 2)]),
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
        back,
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
          const SingleActivator(LogicalKeyboardKey.space): () => _type(' '),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _caret(-1),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _caret(1),
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
