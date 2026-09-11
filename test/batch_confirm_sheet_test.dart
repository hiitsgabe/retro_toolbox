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

  testWidgets('o cabeçalho conta as incertezas, e some quando não há nenhuma', (tester) async {
    // O selo por linha já tinha teste; a contagem do cabeçalho não tinha, e
    // ela tem plural próprio. Os três ramos num caso só de propósito: é uma
    // regra de texto, e três casos separados custariam três vezes o mesmo
    // cenário para provar a mesma frase.
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certo.zip', 1024),
      _pick('duvida.zip', 1024, uncertain: true),
      _pick('outra.zip', 1024, uncertain: true),
    ])));
    expect(find.text('2 incertos'), findsOneWidget);

    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certo.zip', 1024),
      _pick('duvida.zip', 1024, uncertain: true),
    ])));
    expect(find.text('1 incerto'), findsOneWidget);

    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('certo.zip', 1024)])));
    expect(find.textContaining('incerto'), findsNothing);
  });

  testWidgets('Cancelar fecha a folha sem confirmar nada', (tester) async {
    // Precisa de rota de verdade: a folha chama `maybePop`, e com ela montada
    // direto no `body` não há o que desempilhar, então o teste passaria sem
    // provar nada. Aqui ela sobe como modal, do jeito que `_confirmarLote`
    // sobe em produção.
    var confirmou = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<BatchPlan>(
              context: context,
              builder: (_) => BatchConfirmSheet(
                plan: BatchPlan(picks: [_pick('a.zip', 1024)]),
                onConfirm: (_) => confirmou++,
                onRemove: (_) {},
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byType(BatchConfirmSheet), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(BatchConfirmSheet), findsNothing);
    expect(confirmou, 0);
  });

  testWidgets('só com falhas o cabeçalho diz zero jogos, e a folha continua aberta', (tester) async {
    // A folha não se fecha sozinha quando nada pode ser baixado: ela existe
    // justamente para mostrar o motivo (seção 6). O cabeçalho tem que dizer a
    // verdade nesse estado, e o plural de zero é "jogos".
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'sem fonte')],
    )));

    expect(find.text('0 jogos, 0 B'), findsOneWidget);
    expect(find.text('sem fonte'), findsOneWidget);
  });
}
