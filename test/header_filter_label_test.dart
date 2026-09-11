import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/header/header.dart';

void main() {
  test('em MODO FONTE o rótulo é o de hoje, sem uma letra mudada', () {
    // MODO FONTE é o app de hoje. Mudar este texto é regressão, e a Task 22
    // trata regressão de MODO FONTE como falha da fatia.
    expect(filterButtonLabel(GridMode.source), 'Filters');
  });

  test('em MODO PACK o rótulo diz só o que o funil ainda faz', () {
    // Em MODO PACK a grade não passa pelo FilteringService, então revisão e
    // qualidade de dump não filtram nada. Região sobrevive porque alimenta a
    // escolha de versão em `planFromEntries`. Ver "Quinta decisão travada".
    expect(filterButtonLabel(GridMode.pack), 'Preferência de região');
  });
}
