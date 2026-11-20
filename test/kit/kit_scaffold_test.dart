import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

import 'kit_support.dart';

void main() {
  KitScaffold tool({ActionBar? bar, AppArea? area, Widget? body}) => KitScaffold(
        title: 'CHD Converter',
        subtitle: 'Compress disc images to .chd, or extract them',
        icon: Icons.album_outlined,
        info: const InfoButton(icon: Icons.album_outlined, text: 'All about CHD.'),
        area: area,
        body: body ?? const SizedBox.expand(),
        actionBar: bar,
      );

  testWidgets('the header holds the title, the one-line subtitle and the (i)', (t) async {
    await pumpKit(t, tool(), style: CardStyle.vita);
    expect(find.text('CHD Converter'), findsOneWidget);
    final sub = t.widget<Text>(find.byKey(const ValueKey('kit-subtitle')));
    expect(sub.data, 'Compress disc images to .chd, or extract them');
    expect(sub.maxLines, 1);
    expect(find.byType(InfoButton), findsOneWidget);
  });

  testWidgets('Classic writes titles in capitals, the other styles as given', (t) async {
    await pumpKit(t, tool(), style: CardStyle.classic);
    expect(find.text('CHD CONVERTER'), findsOneWidget);
    await pumpKit(t, tool(), style: CardStyle.switchStyle);
    expect(find.text('CHD Converter'), findsOneWidget);
  });

  testWidgets('back shows on a pushed screen and pops it', (t) async {
    await pumpKit(t, pushed(tool()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kit-back')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kit-back')));
    await t.pumpAndSettle();
    expect(find.text('first page'), findsOneWidget);
  });

  testWidgets('no back on the first route', (t) async {
    await pumpKit(t, tool());
    expect(find.byKey(const ValueKey('kit-back')), findsNothing);
  });

  testWidgets('Start runs the primary wherever focus is on the screen', (t) async {
    var ran = 0, pressed = 0;
    await pumpKit(
      t,
      tool(
        bar: ActionBar(primary: KitAction('Compress to CHD', () => ran++)),
        body: Center(child: TextButton(autofocus: true, onPressed: () => pressed++, child: const Text('focused'))),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pump();
    expect(ran, 1);
    expect(pressed, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pump();
    expect(ran, 2);
  });

  testWidgets('Start with the primary disabled does nothing, not even press the focused control', (t) async {
    var pressed = 0;
    await pumpKit(
      t,
      tool(
        bar: const ActionBar(primary: KitAction('Compress to CHD', null)),
        body: Center(child: TextButton(autofocus: true, onPressed: () => pressed++, child: const Text('focused'))),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pump();
    expect(pressed, 0);
  });

  testWidgets('in Classic the area colour is the accent of the controls under the screen', (t) async {
    // The colour the button paints, wherever the theme put it.
    Color? fill(WidgetTester t) => t.widget<Material>(find.descendant(of: find.byKey(const ValueKey('kit-primary')), matching: find.byType(Material)).first).color;
    final bar = ActionBar(primary: KitAction('Go', () {}));
    await pumpKit(t, tool(bar: bar, area: AppArea.tools), style: CardStyle.classic);
    expect(fill(t), StyleTokens.areaPalette[AppArea.tools]);
    await pumpKit(t, tool(bar: bar, area: AppArea.tools), style: CardStyle.vita);
    expect(fill(t), StyleTokens.vita.accent);
  });

  group('KitColumns', () {
    Widget columns({bool endFirst = false, List<Widget>? end}) => KitScaffold(
          title: 'T',
          body: KitColumns(
            start: const [Text('inputs')],
            end: end ?? const [Text('status')],
            endFirstWhenStacked: endFirst,
          ),
        );

    testWidgets('two columns side by side on Odin 2 and the 640x480', (t) async {
      for (final d in [odin2, linux640]) {
        await pumpKit(t, columns(), device: d);
        final a = t.getTopLeft(find.text('inputs')), b = t.getTopLeft(find.text('status'));
        expect(b.dx, greaterThan(a.dx + 200), reason: '$d');
        expect(b.dy, a.dy, reason: '$d');
      }
    });

    testWidgets('one column on a phone, the end first when asked', (t) async {
      await pumpKit(t, columns(), device: phone);
      expect(t.getTopLeft(find.text('status')).dy, greaterThan(t.getTopLeft(find.text('inputs')).dy));
      expect(t.getTopLeft(find.text('status')).dx, t.getTopLeft(find.text('inputs')).dx);
      await pumpKit(t, columns(endFirst: true), device: phone);
      expect(t.getTopLeft(find.text('status')).dy, lessThan(t.getTopLeft(find.text('inputs')).dy));
    });

    testWidgets('a hidden status panel leaves no gap', (t) async {
      await pumpKit(t, columns(endFirst: true, end: const [StatusPanel.hidden()]), device: phone);
      final withHidden = t.getTopLeft(find.text('inputs')).dy;
      await pumpKit(t, columns(endFirst: true, end: const []), device: phone);
      expect(t.getTopLeft(find.text('inputs')).dy, withHidden);
    });
  });

  testWidgets('a wizard step shows as segments in landscape and a bar in portrait', (t) async {
    const s = KitScaffold(title: 'Setup', progress: KitProgress(1, 3), body: SizedBox());
    await pumpKit(t, s);
    expect(find.descendant(of: find.byKey(const ValueKey('kit-progress')), matching: find.byType(Container)), findsNWidgets(3));
    await pumpKit(t, s, device: phone);
    expect(find.byKey(const ValueKey('kit-progress')), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('kit-progress'))).width, greaterThan(300));
  });
}
