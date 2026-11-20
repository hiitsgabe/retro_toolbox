import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  Future<TextEditingController> pump(WidgetTester t, {String? error, String? message, ValueChanged<String>? onChanged}) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await pumpKit(
      t,
      Scaffold(
        body: KitPanel(children: [
          FieldSlot(label: 'Link', controller: c, hint: 'https://', error: error, message: message, onChanged: onChanged, trailing: const Icon(Icons.content_paste)),
        ]),
      ),
    );
    return c;
  }

  testWidgets('a label over a field that types, with its trailing control', (t) async {
    final typed = <String>[];
    final c = await pump(t, onChanged: typed.add);
    expect(find.text('Link'), findsOneWidget);
    expect(find.byIcon(Icons.content_paste), findsOneWidget);
    await t.enterText(find.byType(TextField), 'https://h/a.zip');
    expect(c.text, 'https://h/a.zip');
    expect(typed.last, 'https://h/a.zip');
  });

  testWidgets('the message under the field is shown whole; an error takes its place', (t) async {
    final long = 'https://h/a.zip?sig=${'x' * 400}';
    await pump(t, message: long);
    final paragraph = t.renderObject<RenderParagraph>(find.byKey(const ValueKey('kit-field-message')));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(find.text(long), findsOneWidget);

    await pump(t, error: 'Enter an http or https link', message: long);
    expect(find.text('Enter an http or https link'), findsOneWidget);
    expect(find.text(long), findsNothing);
  });
}
