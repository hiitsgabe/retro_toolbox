import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';

/// The published index for the recipe files in [dir], or why it cannot be
/// built. Every file must be UTF-8 and parse, its id must match its name, and
/// no package may be named by two recipes; one that fails stops the whole
/// index, so a broken recipe never reaches a device. `index.json` itself is
/// never read as a recipe.
({String? json, Map<String, String> problems}) buildRecipeIndex(Directory dir) {
  final bytes = <String, List<int>>{};
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.json') && name != 'index.json') bytes[name] = f.readAsBytesSync();
  }
  final texts = <String, String>{};
  final notUtf8 = <String, String>{};
  for (final e in bytes.entries) {
    try {
      texts[e.key] = utf8.decode(e.value);
    } on FormatException catch (err) {
      notUtf8[e.key] = 'not valid UTF-8: ${err.message}';
    }
  }
  final load = parseRecipeFiles(texts);
  // The device looks a recipe up by package, one entry each, so a package two
  // recipes claim would be decided by map order. Named on the later id.
  final owner = <String, String>{};
  final shared = <String, String>{};
  for (final r in [...load.recipes]..sort((a, b) => a.id.compareTo(b.id))) {
    for (final p in r.packages) {
      final other = owner[p];
      if (other != null && other != r.id) {
        shared['${r.id}.json'] ??= 'package $p is also named by $other';
      } else {
        owner[p] = r.id;
      }
    }
  }
  final problems = {
    ...notUtf8,
    ...load.rejected,
    for (final f in load.tooNew) f: 'schema newer than this app',
    ...shared,
  };
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
