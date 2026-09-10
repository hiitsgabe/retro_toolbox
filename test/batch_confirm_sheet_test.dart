import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/widgets/game_grid/batch_confirm_sheet.dart';

SourcePick _pick(String name, int size, {bool uncertain = false}) => SourcePick(
      gameId: 'snes/$name',
      title: name,
      filename: name,
      size: size,
      sourceId: 'listagem',
      reason: 'escolhido pela sua região preferida',
      uncertain: uncertain,
      game: Game(title: name, url: 'https://exemplo/$name', size: size, consoleId: 'snes'),
    );

Widget _host(BatchPlan plan, {ValueChanged<BatchPlan>? onConfirm, ValueChanged<String>? onRemove}) {
  return MaterialApp(
    home: Scaffold(
      body: BatchConfirmSheet(
        plan: plan,
        onConfirm: onConfirm ?? (_) {},
        onRemove: onRemove ?? (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('mostra a contagem e o total no cabeçalho', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('a.zip', 1024 * 1024),
      _pick('b.zip', 1024 * 1024),
    ])));

    expect(find.text('2 jogos, 2.0 MB'), findsOneWidget);
  });

  testWidgets('usa singular com um jogo só', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('a.zip', 1024)])));

    expect(find.text('1 jogo, 1.0 KB'), findsOneWidget);
  });

  testWidgets('lista o nome do arquivo e o motivo de cada escolha', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('Chrono.zip', 1024)])));

    expect(find.text('Chrono.zip'), findsOneWidget);
    expect(find.text('escolhido pela sua região preferida'), findsOneWidget);
  });

  testWidgets('marca com selo só as escolhas incertas', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certo.zip', 1024),
      _pick('duvida.zip', 1024, uncertain: true),
    ])));

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('separa os que não entram na fila, com o motivo', (tester) async {
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'Sem Fonte', reason: 'nenhum addon tem este jogo')],
    )));

    expect(find.text('Não vão para a fila'), findsOneWidget);
    expect(find.text('Sem Fonte'), findsOneWidget);
    expect(find.text('nenhum addon tem este jogo'), findsOneWidget);
  });

  testWidgets('o botão de remover devolve o gameId daquela linha', (tester) async {
    final removed = <String>[];
    await tester.pumpWidget(_host(
      BatchPlan(picks: [_pick('a.zip', 1024), _pick('b.zip', 1024)]),
      onRemove: removed.add,
    ));

    await tester.tap(find.byKey(const ValueKey('remove-snes/b.zip')));
    await tester.pump();

    expect(removed, ['snes/b.zip']);
  });

  testWidgets('confirmar devolve o plano inteiro', (tester) async {
    BatchPlan? confirmado;
    final plan = BatchPlan(picks: [_pick('a.zip', 1024)]);
    await tester.pumpWidget(_host(plan, onConfirm: (p) => confirmado = p));

    await tester.tap(find.text('Baixar'));
    await tester.pump();

    expect(confirmado, same(plan));
  });

  testWidgets('sem escolha nenhuma o botão de baixar fica desligado', (tester) async {
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'sem fonte')],
    )));

    final botao = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Baixar'));
    expect(botao.onPressed, isNull);
  });
}
