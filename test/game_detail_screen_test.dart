import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/screens/game_detail_screen.dart';

import 'support/favorites_stub.dart';

const _alvo = PackTarget('snes', 'Super Nintendo');

PackGame _pg() => const PackGame(
      id: 'snes/chrono-trigger',
      title: 'Chrono Trigger',
      dumps: [PackDump(name: 'Chrono Trigger (USA)')],
      synopsis: 'Um garoto, uma feira e uma máquina do tempo.',
      genre: 'RPG',
      publisher: 'Square',
      year: 1995,
    );

// Sem `cover` de propósito em todo teste: com URL, o `CachedNetworkImage`
// tentaria rede dentro do teste.
PackGridEntry _entrada({List<MatchedSource> fontes = const []}) =>
    PackGridEntry(game: _pg(), sources: fontes);

MatchedSource _fonte(String filename, {int size = 4 * 1024 * 1024}) => MatchedSource(
      filename: filename,
      sourceId: kBuiltinSourceId,
      confidence: MatchConfidence.likely,
      size: size,
    );

Game _game(String filename) => Game(
      title: filename,
      url: 'https://exemplo.org/snes/$filename',
      size: 4 * 1024 * 1024,
      consoleId: 'snes',
    );

Widget _host(
  PackGridEntry entrada, {
  void Function(SourcePick)? onDownload,
}) {
  return ProviderScope(
    overrides: [
      semDiscoDeFavoritos,
      packTargetProvider.overrideWithValue(_alvo),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue((source) => _game(source.filename)),
    ],
    child: MaterialApp(
      home: GameDetailScreen(entry: entrada, onDownload: onDownload ?? (_) {}),
    ),
  );
}

void main() {
  testWidgets('mostra título, sistema, ano, publisher e gênero', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    expect(find.text('Chrono Trigger'), findsWidgets);
    expect(find.text('Super Nintendo, 1995, Square, RPG'), findsOneWidget);
  });

  testWidgets('mostra a sinopse', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    expect(find.text('Um garoto, uma feira e uma máquina do tempo.'), findsOneWidget);
  });

  testWidgets('o card de destaque traz arquivo, tamanho e motivo', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
    ])));

    expect(find.text('Chrono Trigger (USA).zip'), findsOneWidget);
    expect(find.text('4.0 MB, listagem'), findsOneWidget);
    // O motivo é obrigatório, não decorativo (seção 7).
    expect(find.text('escolhido pela sua região preferida (USA)'), findsOneWidget);
  });

  testWidgets('o botão Baixar devolve a escolha inteira', (tester) async {
    final baixados = <String>[];
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      onDownload: (pick) => baixados.add(pick.game.filename),
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Baixar'));
    await tester.pump();

    // O `Game` que sai do callback é o que a fila entende, não um sintético.
    expect(baixados, ['Chrono Trigger (USA).zip']);
  });

  testWidgets('sem fonte a tela abre inteira e sem card de destaque', (tester) async {
    await tester.pumpWidget(_host(_entrada()));

    // Os 3% da seção 3.1: o jogo continua existindo e continua favoritável.
    expect(find.text('Um garoto, uma feira e uma máquina do tempo.'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Baixar'), findsNothing);
  });

  testWidgets('o coração alterna o favorito', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('o checkbox alterna a seleção pela chave de pack', (tester) async {
    late WidgetRef capturado;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        semDiscoDeFavoritos,
        packTargetProvider.overrideWithValue(_alvo),
        preferredRegionsProvider.overrideWithValue(const {'USA'}),
        gameResolverProvider.overrideWithValue((source) => _game(source.filename)),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          capturado = ref;
          return GameDetailScreen(
            entry: _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
            onDownload: (_) {},
          );
        }),
      ),
    ));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(
      capturado.read(catalogProvider).selectedGames,
      contains('pack:snes/chrono-trigger'),
    );
  });
}
