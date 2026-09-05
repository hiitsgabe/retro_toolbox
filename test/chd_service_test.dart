import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/chd_service.dart';

void main() {
  test('modeForInput: .chd extracts, everything else compresses', () {
    expect(ChdService.modeForInput('game.chd'), ChdMode.extract);
    expect(ChdService.modeForInput('game.cue'), ChdMode.compress);
    expect(ChdService.modeForInput('game.ISO'), ChdMode.compress);
  });

  test('planFor: picks the right chdman subcommand per extension', () {
    expect(ChdService.planFor('g.cue')?.command, 'createcd');
    expect(ChdService.planFor('g.gdi')?.command, 'createcd');
    expect(ChdService.planFor('g.iso')?.command, 'createdvd');
    expect(ChdService.planFor('g.chd')?.command, 'extractcd');
    expect(ChdService.planFor('g.chd')?.outExt, '.cue');
    expect(ChdService.planFor('g.cue')?.outExt, '.chd');
    expect(ChdService.planFor('g.txt'), isNull);
  });

  test('parseProgress reads chdman percentage lines', () {
    expect(ChdService.parseProgress('Compressing, 0.0% complete...'), 0.0);
    expect(ChdService.parseProgress('Compressing, 42.3% complete...'), closeTo(0.423, 1e-9));
    expect(ChdService.parseProgress('Extracting, 100.0% complete'), 1.0);
    expect(ChdService.parseProgress('Output CHD:   game.chd'), isNull);
  });
}
