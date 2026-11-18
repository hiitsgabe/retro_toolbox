import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';

const _game = Game(title: 'F-Zero.zip', url: 'https://h/f.zip', size: 1, consoleId: 'snes', details: GameDetails(boxart: 'https://h/f.png'));

Future<void> _pump(WidgetTester t, {required bool fill}) => t.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 120,
          height: 120,
          child: GameBoxart(game: _game, fill: fill, placeholder: const ColoredBox(key: ValueKey('style-placeholder'), color: Colors.red)),
        ),
      ),
    ));

bool _hasBorder(WidgetTester t) => t
    .widgetList<Container>(find.byType(Container))
    .any((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).border != null);

void main() {
  testWidgets('a card style fill draws no border and shows the style placeholder while the art loads', (t) async {
    await _pump(t, fill: true);
    expect(_hasBorder(t), isFalse);
    expect(find.byKey(const ValueKey('style-placeholder')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the default keeps its border and its own loading look', (t) async {
    await _pump(t, fill: false);
    expect(_hasBorder(t), isTrue);
    expect(find.byKey(const ValueKey('style-placeholder')), findsNothing);
  });
}
