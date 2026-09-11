import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';

Widget _host({required int count, VoidCallback? onClear, VoidCallback? onDownload}) {
  return MaterialApp(
    home: Scaffold(
      body: SelectionBar(
        count: count,
        onClear: onClear ?? () {},
        onDownload: onDownload ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('não ocupa altura nenhuma quando a seleção está vazia', (tester) async {
    await tester.pumpWidget(_host(count: 0));

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Baixar'), findsNothing);
    expect(tester.getSize(find.byType(SelectionBar)).height, 0);
  });

  testWidgets('conta no singular com um item', (tester) async {
    await tester.pumpWidget(_host(count: 1));

    expect(find.text('1 selecionado'), findsOneWidget);
  });

  testWidgets('conta no plural com mais de um item', (tester) async {
    await tester.pumpWidget(_host(count: 3));

    expect(find.text('3 selecionados'), findsOneWidget);
  });

  testWidgets('ocupa exatamente 48 de altura com seleção', (tester) async {
    await tester.pumpWidget(_host(count: 3));

    // O contrário do primeiro caso, e não uma redundância dele: o `IconButton`
    // e o `FilledButton` medem 48 sozinhos por causa do alvo de toque padrão
    // do Material, então o `SizedBox(height: 48)` não tem folga nenhuma.
    // Qualquer padding a mais estoura a faixa, e sem este caso nada avisa.
    expect(tester.getSize(find.byType(SelectionBar)).height, 48);
  });

  testWidgets('o × chama onClear e o botão chama onDownload', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(_host(
      count: 3,
      onClear: () => fired.add('clear'),
      onDownload: () => fired.add('download'),
    ));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.tap(find.text('Baixar'));
    await tester.pump();

    expect(fired, ['clear', 'download']);
  });
}
