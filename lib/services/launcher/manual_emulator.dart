/// An emulator the user added by hand, for an app or executable detection
/// does not know: paired with a preset of the file it opens games like, or
/// with none ([ManualEmulator.generic]: it gets the game file as a viewer
/// would). Pure Dart, like launch_preset.dart.
library;

class ManualEmulator {
  const ManualEmulator({required this.variant, required this.label, required this.recipe, this.systems = const [], this.activity});

  /// No recipe: on Android ACTION_VIEW on our provider URI, on desktop the
  /// file's path as the only argument.
  static const generic = 'generic';

  /// The Android package, or the desktop executable's path.
  final String variant;

  /// What the user saw when picking it: the app's label, or the file's name.
  final String label;

  /// A preset id of the file, or [generic].
  final String recipe;

  /// Console art slugs. With a recipe, empty is all of the recipe's; a
  /// generic one has at least one, the consoles the user ticked.
  final List<String> systems;

  /// Android generic only: the activity viewActivity found when it was added.
  final String? activity;

  bool get isGeneric => recipe == generic;

  /// The preset id it goes by. Derived from the variant, so adding the same
  /// app again replaces it, and a default or override naming it outlives a
  /// restart.
  String get id => manualId(variant);

  Map<String, Object?> toJson() => {'variant': variant, 'label': label, 'recipe': recipe, 'systems': systems, if (activity != null) 'activity': activity};

  /// Null for anything that is not a saved manual emulator, so one bad entry
  /// never costs the others.
  static ManualEmulator? fromJson(Object? j) {
    if (j is! Map) return null;
    final variant = j['variant'], label = j['label'], recipe = j['recipe'], systems = j['systems'], activity = j['activity'];
    if (variant is! String || variant.isEmpty || label is! String || recipe is! String || recipe.isEmpty) return null;
    if (systems != null && systems is! List) return null;
    if (activity != null && activity is! String) return null;
    final slugs = [
      if (systems is List)
        for (final s in systems)
          if (s is String) s,
    ];
    if (recipe == generic && slugs.isEmpty) return null;
    return ManualEmulator(variant: variant, label: label, recipe: recipe, systems: slugs, activity: activity as String?);
  }
}

/// `manual-` and [variant] lowercased, every character outside
/// `[a-z0-9._-]` made a `-`: a preset id is a plain word wherever it goes.
String manualId(String variant) => 'manual-${variant.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '-')}';
