import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/header/header.dart';

void main() {
  test('source mode keeps the current label unchanged', () {
    expect(filterButtonLabel(GridMode.source), 'Filters');
  });

  test('pack mode label names only what the funnel still does', () {
    expect(filterButtonLabel(GridMode.pack), 'Region preference');
  });
}
