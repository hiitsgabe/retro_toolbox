import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';

/// The published index for the recipe files in [dir], or why it cannot be
/// built. Every file must parse and its id must match its name; one that does
/// not stops the whole index, so a broken recipe never reaches a device.
/// `index.json` itself is never read as a recipe.
({String? json, Map<String, String> problems}) buildRecipeIndex(Directory dir) {
  final bytes = <String, List<int>>{};
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.json') && name != 'index.json') bytes[name] = f.readAsBytesSync();
  }
  final load = parseRecipeFiles({for (final e in bytes.entries) e.key: utf8.decode(e.value)});
  final problems = {...load.rejected, for (final f in load.tooNew) f: 'schema newer than this app'};
  if (problems.isNotEmpty) return (json: null, problems: problems);
  final recipes = [...load.recipes]..sort((a, b) => a.id.compareTo(b.id));
  final index = {
    'format': 1,
    'recipes': [
      for (final r in recipes)
        {
          'id': r.id,
          'packages': r.packages,
          'status': r.status.name,
          'sha256': sha256.convert(bytes['${r.id}.json']!).toString(),
        },
    ],
  };
  return (json: '${const JsonEncoder.withIndent('  ').convert(index)}\n', problems: const <String, String>{});
}
