/// Which emulator opens a game: a preset, the variant detected for it (the
/// Android package or the desktop executable), and for RetroArch a core
/// other than the system's first.
class LaunchChoice {
  const LaunchChoice({required this.presetId, required this.variant, this.core});

  final String presetId;
  final String variant;
  final String? core;

  Map<String, Object?> toJson() => {'presetId': presetId, 'variant': variant, if (core != null) 'core': core};

  /// Null for anything that is not a choice, so one bad entry in a saved
  /// file never costs the others.
  static LaunchChoice? fromJson(Object? j) {
    if (j is! Map) return null;
    final presetId = j['presetId'], variant = j['variant'], core = j['core'];
    if (presetId is! String || variant is! String || (core != null && core is! String)) return null;
    return LaunchChoice(presetId: presetId, variant: variant, core: core as String?);
  }

  @override
  bool operator ==(Object other) => other is LaunchChoice && other.presetId == presetId && other.variant == variant && other.core == core;

  @override
  int get hashCode => Object.hash(presetId, variant, core);

  @override
  String toString() => 'LaunchChoice($presetId, $variant${core == null ? '' : ', $core'})';
}
