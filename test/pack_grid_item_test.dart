import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

// `coverUrl` fica nulo em todo teste de propósito: com URL, o
// `CachedNetworkImage` tentaria rede dentro do teste. A capa é coberta à mão.
Widget _host(
  Widget child, {
  double largura = 200,
}) =>
    MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: largura, child: child))));

void main() {
  testWidgets('mostra o título do jogo', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.text('Chrono Trigger'), findsOneWidget);
  });

  testWidgets('sem fonte ganha a marca de nuvem cortada', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('com fonte não ganha marca nenhuma', (tester) async {
    // A premissa da seção 3.1: marca-se a exceção, não a regra.
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
  });

  testWidgets('o tile é igual com fonte confirmada e com fonte no chute', (tester) async {
    // Não existe parâmetro de confiança neste widget, e este teste existe para
    // que a ausência seja intencional e visível. Se alguém acrescentar
    // `confidence:` aqui, este teste não compila mais e é isso que se quer.
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
  });

  testWidgets('sem seleção ativa não há checkbox', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      selectionActive: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('com seleção ativa todo tile mostra checkbox, marcado ou não', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      selectionActive: true,
      isSelected: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('o tile selecionado mostra o checkbox marcado', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      selectionActive: true,
      isSelected: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('toque curto abre e toque longo seleciona', (tester) async {
    var abriu = 0;
    var selecionou = 0;
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () => abriu++,
      onLongPress: () => selecionou++,
      onToggleSelection: () {},
    )));

    await tester.tap(find.byType(PackGridItem));
    await tester.longPress(find.byType(PackGridItem));
    await tester.pump();

    expect(abriu, 1);
    expect(selecionou, 1);
  });

  testWidgets('o checkbox alterna a seleção sem abrir o detalhe', (tester) async {
    var abriu = 0;
    var alternou = 0;
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      selectionActive: true,
      onTap: () => abriu++,
      onLongPress: () {},
      onToggleSelection: () => alternou++,
    )));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(alternou, 1);
    expect(abriu, 0);
  });

  testWidgets('a borda grossa aparece quando o jogo já está no disco', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      isOwned: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    final borda = tester.widget<Container>(find.byKey(const ValueKey('pack-tile-border')));
    expect((borda.decoration as BoxDecoration).border!.top.width, 3);
  });

  testWidgets('sem estado nenhum a borda é fina', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Chrono Trigger',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    final borda = tester.widget<Container>(find.byKey(const ValueKey('pack-tile-border')));
    expect((borda.decoration as BoxDecoration).border!.top.width, 1);
  });
}
