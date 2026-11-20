import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_list.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kit/kit_support.dart';
import 'screenshots/fakes.dart';

/// A game with every chip a card can show: discs, revision, regions, tags.
const _game = Game(
  title: 'Final Fantasy VII (USA) (Disc 1) (Rev 1) (Beta)',
  url: 'https://example.invalid/psx/ff7.zip',
  size: 4 << 20,
  consoleId: 'snes',
  metadata: GameMetadata(
    displayTitle: 'Final Fantasy VII',
    diskNumber: '1',
    revision: '1',
    regions: ['USA', 'Europe', 'Japan', 'Korea'],
    romTypes: {RomType.beta},
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// [card] at about its size in the grid (six across on an Odin 2) or the
  /// list (the screen's width).
  Future<void> pump(WidgetTester t, Widget card, (Size, double) device) async {
    final size = card is GameRow ? const Size(double.infinity, 0) : const Size(112, 150);
    await pumpKit(
      t,
      // A list row takes the height it needs, as in the list.
      Scaffold(body: Center(child: SizedBox(width: size.width, height: card is GameRow ? null : size.height, child: card))),
      device: device,
      overrides: [
        ...gamesOverrides([_game]),
        gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: GameStatus.downloading, currentProgress: 0.42, showProgressBar: true)),
      ],
    );
    await t.pump(const Duration(milliseconds: 100));
  }

  for (final (name, device) in [('odin2', odin2), ('linux640', linux640)]) {
    for (final (kind, card) in [('grid card', const GameGridItem(game: _game)), ('list row', const GameRow(game: _game))]) {
      // Disc, revision and region chips and the progress line were 8 and 9 px.
      testWidgets('$name $kind: no chip or badge text under the device floor', (t) async {
        await pump(t, card, device);
        final floor = DeviceClass.from(device.$1, device.$2).textFloor;
        final texts = find.descendant(of: find.byType(card.runtimeType), matching: find.byType(Text));
        expect(texts, findsWidgets);
        for (final e in texts.evaluate()) {
          final size = (e.widget as Text).style?.fontSize;
          if (size != null) expect(size, greaterThanOrEqualTo(floor), reason: (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText());
        }
      });
    }
  }

  // Without art the face was a 30% wash: the cover flow's cards behind it
  // showed through.
  testWidgets('a card without art is opaque', (t) async {
    await pump(t, const GameGridItem(game: _game), odin2);
    final face = t.widget<Container>(find.byKey(const ValueKey('game-placeholder')));
    final colors = ((face.decoration as BoxDecoration).gradient as LinearGradient).colors;
    for (final c in colors) {
      expect(c.a, 1.0);
    }
  });

  // The Status column took a phone row's width: titles were cut to a word.
  testWidgets('on a phone the list has no Status column; a row says its state after its size', (t) async {
    final games = snesGames();
    await pumpKit(t, const Scaffold(body: GameList()), device: phone, overrides: gamesOverrides(games));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Status'), findsNothing);
    expect(find.text('Ready'), findsNothing, reason: 'no column of its own');
    final line = t.widget<Text>(find.byKey(const ValueKey('row-size-status')).first);
    expect(line.textSpan!.toPlainText(), contains('Ready'));
    // The test font draws every glyph a square: twelve of them fit now, not before.
    expect(t.renderObject<RenderParagraph>(find.text('F-Zero (USA)')).didExceedMaxLines, isFalse, reason: 'the title whole');
  });

  testWidgets('on the Odin 2 the Status column stays', (t) async {
    await pumpKit(t, const Scaffold(body: GameList()), overrides: gamesOverrides(snesGames()));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Status'), findsOneWidget);
  });
}
