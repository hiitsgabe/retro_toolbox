import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/providers/owned_games_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_index.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

import 'support/favorites_stub.dart';

PackGame _pg(String id, String title) => PackGame(id: id, title: title, dumps: [PackDump(name: '$title (USA)')]);

PackGridEntry _entrada(String id, String title, {bool comFonte = true}) => PackGridEntry(
      game: _pg(id, title),
      sources: comFonte
          ? [MatchedSource(filename: '$title (USA).zip', sourceId: 'listagem', confidence: MatchConfidence.likely, size: 1024)]
          : const [],
    );

/// Um índice de verdade, porque a faixa de estado vazio lê `matchedGameCount`
/// e um índice falso não provaria nada.
SourceIndex _indice({required bool casaAlgo}) {
  final matcher = PackMatcher(MetadataPack(
    pack: 'snes',
    system: 'Super Nintendo',
    built: '2026-01-01',
    games: [_pg('snes/chrono-trigger', 'Chrono Trigger')],
  ));
  return SourceIndex.build(matcher, [
    if (casaAlgo)
      (filename: 'Chrono Trigger (USA).zip', sourceId: 'listagem', size: 1024, url: null),
  ]);
}

Widget _host(
  List<PackGridEntry> entradas, {
  SourceIndex? indice,
  void Function(PackGridEntry)? onOpenGame,
  Set<String>? baixados,
  bool varrendo = false,
}) {
  return ProviderScope(
    overrides: [
      // Continua aqui, e é a linha mais fácil de perder nesta troca: o
      // `catalogProvider` deste teste é o de verdade, e o construtor dele
      // escuta `favoritesProvider`, que vai ao disco. Sem o stub o caso do
      // toque longo estoura com `MissingPluginException` **depois** de ter
      // passado. Ver a "Sexta decisão travada".
      semDiscoDeFavoritos,
      packGridEntriesProvider.overrideWithValue(entradas),
      sourceIndexProvider.overrideWithValue(indice ?? _indice(casaAlgo: true)),
      ownedGameIdsProvider.overrideWith(
        // Um `Completer` que ninguém completa é a varredura em curso. Um
        // `Future.delayed` deixaria timer pendente e o teste falharia no fim.
        (ref) => varrendo ? Completer<Set<String>>().future : Future.value(baixados ?? const <String>{}),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: PackGrid(onOpenGame: onOpenGame ?? (_) {})),
    ),
  );
}

void main() {
  testWidgets('desenha um tile por entrada', (tester) async {
    await tester.pumpWidget(_host([
      _entrada('snes/chrono-trigger', 'Chrono Trigger'),
      _entrada('snes/super-metroid', 'Super Metroid'),
    ]));

    expect(find.byType(PackGridItem), findsNWidgets(2));
    expect(find.text('Chrono Trigger'), findsOneWidget);
  });

  testWidgets('o jogo sem fonte continua na grade, marcado', (tester) async {
    await tester.pumpWidget(_host([
      _entrada('snes/chrono-trigger', 'Chrono Trigger'),
      _entrada('snes/earthbound', 'EarthBound', comFonte: false),
    ]));

    expect(find.byType(PackGridItem), findsNWidgets(2));
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('com o índice vazio aparece a faixa de sem cobertura', (tester) async {
    await tester.pumpWidget(_host(
      [_entrada('snes/chrono-trigger', 'Chrono Trigger', comFonte: false)],
      indice: _indice(casaAlgo: false),
    ));

    expect(find.text('Nenhuma fonte cobre este console'), findsOneWidget);
    // A faixa é estado da grade, não do tile: os tiles continuam lá.
    expect(find.byType(PackGridItem), findsOneWidget);
  });

  testWidgets('com o índice cobrindo alguma coisa não há faixa', (tester) async {
    await tester.pumpWidget(_host([_entrada('snes/chrono-trigger', 'Chrono Trigger')]));

    expect(find.text('Nenhuma fonte cobre este console'), findsNothing);
  });

  testWidgets('busca sem resultado mostra o vazio de busca, não o de cobertura', (tester) async {
    await tester.pumpWidget(_host(const []));

    expect(find.text('Nenhum jogo com esse nome'), findsOneWidget);
    expect(find.text('Nenhuma fonte cobre este console'), findsNothing);
  });

  testWidgets('o toque curto devolve a entrada tocada', (tester) async {
    final abertas = <String>[];
    await tester.pumpWidget(_host(
      [_entrada('snes/chrono-trigger', 'Chrono Trigger'), _entrada('snes/super-metroid', 'Super Metroid')],
      onOpenGame: (entry) => abertas.add(entry.game.id),
    ));

    await tester.tap(find.text('Super Metroid'));
    await tester.pump();

    expect(abertas, ['snes/super-metroid']);
  });

  testWidgets('o toque longo seleciona, e aí o checkbox aparece em todo tile', (tester) async {
    await tester.pumpWidget(_host([
      _entrada('snes/chrono-trigger', 'Chrono Trigger'),
      _entrada('snes/super-metroid', 'Super Metroid'),
    ]));

    expect(find.byType(Checkbox), findsNothing);

    await tester.longPress(find.text('Chrono Trigger'));
    await tester.pump();

    // Dois checkboxes, um marcado. É a regra da seção 4: a visibilidade do
    // checkbox é global, o valor dele é por tile.
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).where((c) => c.value == true).length,
      1,
    );
  });

  testWidgets('o jogo que já está no disco vai marcado para o tile', (tester) async {
    await tester.pumpWidget(_host(
      [
        _entrada('snes/chrono-trigger', 'Chrono Trigger'),
        _entrada('snes/super-metroid', 'Super Metroid'),
      ],
      baixados: {'snes/chrono-trigger'},
    ));
    await tester.pump();

    final tiles = tester.widgetList<PackGridItem>(find.byType(PackGridItem)).toList();
    expect(tiles.firstWhere((t) => t.title == 'Chrono Trigger').isOwned, isTrue);
    expect(tiles.firstWhere((t) => t.title == 'Super Metroid').isOwned, isFalse);
  });

  testWidgets('enquanto a varredura não termina ninguém vai marcado', (tester) async {
    await tester.pumpWidget(_host(
      [_entrada('snes/chrono-trigger', 'Chrono Trigger')],
      baixados: {'snes/chrono-trigger'},
      varrendo: true,
    ));
    await tester.pump();

    // Seção 3.1: nada de borda enquanto o scan roda. Borda errada é pior que
    // borda ausente, e neste instante a resposta ainda não existe.
    expect(tester.widget<PackGridItem>(find.byType(PackGridItem)).isOwned, isFalse);
  });
}
