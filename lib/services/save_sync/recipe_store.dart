import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';

class RecipeLoad {
  const RecipeLoad(this.recipes, this.rejected, this.tooNew);

  final List<Recipe> recipes;

  /// File name to the reason it was refused.
  final Map<String, String> rejected;

  /// Files whose schema is newer than this app understands.
  final List<String> tooNew;
}

/// Parses recipe files (name to JSON text). A file's id must equal its name
/// without `.json`, so two files can never claim the same id.
RecipeLoad parseRecipeFiles(Map<String, String> files) {
  final recipes = <Recipe>[];
  final rejected = <String, String>{};
  final tooNew = <String>[];
  for (final e in (files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
    try {
      final json = jsonDecode(e.value);
      if (json is! Map<String, dynamic>) throw RecipeError('not a JSON object');
      final r = Recipe.parse(json);
      if ('${r.id}.json' != e.key) throw RecipeError('id "${r.id}" does not match the file name');
      recipes.add(r);
    } on RecipeTooNew {
      tooNew.add(e.key);
    } on RecipeError catch (err) {
      rejected[e.key] = err.message;
    } on FormatException catch (err) {
      rejected[e.key] = 'invalid JSON: ${err.message}';
    }
  }
  return RecipeLoad(recipes, rejected, tooNew);
}

class RecipeStore {
  RecipeStore({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  /// Recipes written on this device, which win over every other layer: a
  /// person who sat down and described their own app's saves has said more
  /// than any catalog can.
  Future<RecipeLoad> loadUser(Directory dir) async {
    if (!await dir.exists()) return const RecipeLoad([], {}, []);
    final files = <String, String>{};
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) files[e.uri.pathSegments.last] = await e.readAsString();
    }
    return parseRecipeFiles(files);
  }

  /// The recipes shipped inside the app (`save_recipes/` in the repo).
  Future<RecipeLoad> loadBundled() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    final paths = manifest.listAssets().where((a) => a.startsWith('save_recipes/') && a.endsWith('.json'));
    return parseRecipeFiles({for (final a in paths) a.substring('save_recipes/'.length): await _bundle.loadString(a)});
  }
}
