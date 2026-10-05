import 'package:flutter/services.dart';

/// Pure editing logic for the on-screen keyboard. An invalid selection counts
/// as a caret at the end of the text.
class OskController {
  const OskController({this.maxLength});

  final int? maxLength;

  static TextSelection _sel(TextEditingValue v) =>
      v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);

  static TextEditingValue _value(String text, int caret) =>
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret));

  /// Replaces the selection with [s].
  TextEditingValue insert(TextEditingValue v, String s) {
    final sel = _sel(v);
    final text = sel.textBefore(v.text) + s + sel.textAfter(v.text);
    if (maxLength != null && text.length > maxLength!) return v;
    return _value(text, sel.start + s.length);
  }

  /// Deletes the selection, or the character before the caret.
  TextEditingValue backspace(TextEditingValue v) {
    final sel = _sel(v);
    if (!sel.isCollapsed) return _value(sel.textBefore(v.text) + sel.textAfter(v.text), sel.start);
    if (sel.start == 0) return v;
    return _value(v.text.substring(0, sel.start - 1) + v.text.substring(sel.start), sel.start - 1);
  }

  TextEditingValue moveCaret(TextEditingValue v, int delta) =>
      _value(v.text, (_sel(v).extentOffset + delta).clamp(0, v.text.length));
}
