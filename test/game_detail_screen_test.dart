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
import 'package:roms_downloader/services/source_pick_service.dart';

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

MatchedSource _fonte(
  String filename, {
  int size = 4 * 1024 * 1024,
  MatchConfidence confianca = MatchConfidence.likely,
}) =>
    MatchedSource(
      filename: filename,
      sourceId: kBuiltinSourceId,
      confidence: confianca,
      size: size,
    );

Game _game(String filename) => Game(
      title: filename,
      url: 'https://exemplo.org/snes/$filename',
      size: 4 * 1024 * 1024,
      consoleId: 'snes',
    );

// Função de topo, e não variável com lambda, por causa do lint
// `prefer_function_declarations_over_variables`, que vem ligado no
// `flutter_lints`.
Game? _resolvePadrao(MatchedSource source) => _game(source.filename);

Widget _host(
  PackGridEntry entrada, {
  void Function(SourcePick)? onDownload,
  GameResolver? resolver,
}) {
  return ProviderScope(
    overrides: [
      semDiscoDeFavoritos,
      packTargetProvider.overrideWithValue(_alvo),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue(resolver ?? _resolvePadrao),
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

  testWidgets('sem fonte, a faixa diz por que não há de onde baixar', (tester) async {
    await tester.pumpWidget(_host(_entrada()));

    // A mesma string que a folha de lote mostra para o mesmo jogo. Se você
    // acabou de escrever um texto novo aqui, ele já existe em
    // `source_pick_service.dart` e tem que sair de lá.
    expect(find.text('nenhuma fonte instalada tem este jogo'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Baixar'), findsNothing);
  });

  testWidgets('quando a fonte não resolve, a faixa usa o outro motivo', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      resolver: (_) => null,
    ));

    expect(find.text('a fonte saiu da listagem antes de a fila começar'), findsOneWidget);
  });

  testWidgets('sem pick, a fonte que não resolveu ainda aparece na lista', (tester) async {
    await tester.pumpWidget(_host(
      _entrada(fontes: [_fonte('Chrono Trigger (USA).zip')]),
      resolver: (_) => null,
    ));

    // Nada foi escolhido, então nenhuma fonte é "a outra". Mesmo assim a
    // lista abre: esconder o que existe deixaria a faixa parecendo mentira.
    expect(find.text('outra fonte'), findsOneWidget);
  });

  testWidgets('com uma fonte só, não existe lista de outras fontes', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    // Este teste passa antes e depois da implementação. Ele não é uma trava
    // de implementação, é uma trava contra a lista aparecer vazia depois.
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('com três fontes, o contador diz outras 2 fontes', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
      _fonte('Chrono Trigger (Europe).zip'),
    ])));

    expect(find.text('outras 2 fontes'), findsOneWidget);
  });

  testWidgets('com duas fontes, o contador vai no singular', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
    ])));

    // "outras 1 fontes" seria o texto que sai de um contador escrito sem
    // pensar, e o spec de UI escreve contadores em português.
    expect(find.text('outra fonte'), findsOneWidget);
  });

  testWidgets('a lista começa fechada', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
    ])));

    expect(find.text('outra fonte'), findsOneWidget);
    expect(find.text('Chrono Trigger (Japan).zip'), findsNothing);
  });

  testWidgets('expandida, cada linha traz arquivo, tamanho, addon, tipo e confiança', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (Japan).zip'),
      _fonte('Chrono Trigger (USA).zip'),
    ])));

    await tester.tap(find.text('outra fonte'));
    await tester.pumpAndSettle();

    expect(find.text('Chrono Trigger (Japan).zip'), findsOneWidget);
    expect(find.text('4.0 MB, listagem, HTTP, casamento provável'), findsOneWidget);
  });

  testWidgets('a linha de palpite mostra o casamento no chute', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (USA).zip'),
      _fonte('Chrono Trigger (Japan).zip', confianca: MatchConfidence.guess),
    ])));

    await tester.tap(find.text('outra fonte'));
    await tester.pumpAndSettle();

    // É a confiança do casamento, não o CRC. Ver a "Segunda decisão travada".
    expect(find.text('4.0 MB, listagem, HTTP, casamento no chute'), findsOneWidget);
  });

  testWidgets('duas fontes idênticas: a escolhida sai da lista uma vez só', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [
      _fonte('Chrono Trigger (USA).zip', size: 10),
      _fonte('Chrono Trigger (USA).zip', size: 20),
    ])));

    await tester.tap(find.text('outra fonte'));
    await tester.pumpAndSettle();

    // A de 10 bytes venceu pelo desempate de ordem (Task 14). Se a lista
    // tirasse todas as fontes de mesmo nome, a de 20 sumiria junto e o
    // usuário perderia uma fonte real de vista.
    expect(find.text('10.0 B, listagem'), findsOneWidget);
    expect(find.text('20.0 B, listagem, HTTP, casamento provável'), findsOneWidget);
  });

  testWidgets('o card de destaque marca o tipo da fonte', (tester) async {
    await tester.pumpWidget(_host(_entrada(fontes: [_fonte('Chrono Trigger (USA).zip')])));

    // O `HTTP` do canto direito do mockup da seção 7. Com uma fonte só não há
    // lista, então este é o único `HTTP` da tela.
    expect(find.text('HTTP'), findsOneWidget);
  });
}
