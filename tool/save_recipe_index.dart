import 'dart:io';

import 'package:retro_toolbox/services/save_sync/recipe_index_builder.dart';

/// Regenerates save_recipes/index.json. Exits 1, writing nothing, when any
/// recipe fails to parse.
void main() {
  final dir = Directory('save_recipes');
  final built = buildRecipeIndex(dir);
  final json = built.json;
  if (json == null) {
    for (final e in built.problems.entries) {
      stderr.writeln('${e.key}: ${e.value}');
    }
    exitCode = 1;
    return;
  }
  File('${dir.path}/index.json').writeAsStringSync(json);
  stdout.writeln('wrote ${dir.path}/index.json');
}
