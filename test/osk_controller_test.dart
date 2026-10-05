import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/osk/osk_controller.dart';

TextEditingValue v(String t, int caret) =>
    TextEditingValue(text: t, selection: TextSelection.collapsed(offset: caret));

void main() {
  const c = OskController();
  test('insert at caret', () => expect(c.insert(v('ac', 1), 'b'), v('abc', 2)));
  test('insert replaces selection', () {
    final sel = TextEditingValue(text: 'hello', selection: const TextSelection(baseOffset: 1, extentOffset: 4));
    expect(c.insert(sel, 'i'), v('hio', 2));
  });
  test('backspace before caret', () => expect(c.backspace(v('abc', 2)), v('ac', 1)));
  test('backspace at start does nothing', () => expect(c.backspace(v('abc', 0)), v('abc', 0)));
  test('caret clamps', () {
    expect(c.moveCaret(v('ab', 0), -1), v('ab', 0));
    expect(c.moveCaret(v('ab', 2), 1), v('ab', 2));
  });
  test('maxLength', () => expect(const OskController(maxLength: 2).insert(v('ab', 2), 'c'), v('ab', 2)));
}
