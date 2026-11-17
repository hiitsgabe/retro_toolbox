/// Which physical screen the main app takes; the companion gets the other.
enum DualScreenMode { off, mainOnTop, mainOnBottom }

/// A display as Android reports it over `retro_toolbox/dual_screen`.
class DisplayInfo {
  const DisplayInfo({required this.id, required this.isDefault, required this.on});

  factory DisplayInfo.fromJson(Map json) => DisplayInfo(id: json['id'] as int, isDefault: json['isDefault'] == true, on: json['on'] == true);

  final int id;
  final bool isDefault;
  final bool on;
}

class DualScreenPlan {
  const DualScreenPlan({required this.mainDisplay, required this.companionDisplay});

  final int mainDisplay, companionDisplay;
}

/// Where the main activity and the companion go, or null when the mode is off
/// or there is no second display that is on. The default display is the top
/// panel on the AYN Thor; the other is the lowest-id display that is on and
/// not the default. No display id is hardcoded.
DualScreenPlan? planDisplays(DualScreenMode mode, List<DisplayInfo> displays) {
  if (mode == DualScreenMode.off) return null;
  final on = displays.where((d) => d.on).toList()..sort((a, b) => a.id.compareTo(b.id));
  if (on.length < 2) return null;
  // No default among those on (its panel is off): the lowest id stands in.
  final top = on.firstWhere((d) => d.isDefault, orElse: () => on.first).id;
  final other = on.firstWhere((d) => d.id != top).id;
  return mode == DualScreenMode.mainOnTop
      ? DualScreenPlan(mainDisplay: top, companionDisplay: other)
      : DualScreenPlan(mainDisplay: other, companionDisplay: top);
}
