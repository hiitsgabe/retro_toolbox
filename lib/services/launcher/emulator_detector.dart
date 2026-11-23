import 'dart:io';
import 'dart:typed_data';

import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';

/// Which presets are installed: on Android through the native `detect`.
/// Desktop detection comes with the find rules (desktop_finder.dart).
class EmulatorDetector {
  EmulatorDetector({LauncherChannel? channel, String? os})
      : _channel = channel ?? const LauncherChannel(),
        _os = os ?? Platform.operatingSystem;

  final LauncherChannel _channel;
  final String _os;

  Future<List<DetectedEmulator>> detect(List<LaunchPreset> presets) async {
    if (_os == 'android') return _android(presets);
    return const [];
  }

  Future<List<DetectedEmulator>> _android(List<LaunchPreset> presets) async {
    final android = [for (final p in presets) if (p.android != null) p];
    if (android.isEmpty) return const [];
    final facts = await _channel.detect([
      for (final p in android) {'id': p.id, 'packages': p.android!.packages, 'activity': p.android!.activity},
    ]);
    final out = <DetectedEmulator>[];
    for (final preset in android) {
      // The first variant in the preset's order wins, whatever order the
      // native side listed them in.
      for (final pkg in preset.android!.packages) {
        final f = facts.where((f) => f['id'] == preset.id && f['package'] == pkg).firstOrNull;
        if (f == null) continue;
        out.add(_fromFacts(preset, pkg, f));
        break;
      }
    }
    return out;
  }

  DetectedEmulator _fromFacts(LaunchPreset preset, String pkg, Map<String, Object?> f) {
    int intOf(String key) => f[key] is int ? f[key] as int : 0;
    bool boolOf(String key) => f[key] == true;
    final facts = AndroidPackageFacts(
      targetSdk: intOf('targetSdk'),
      sdkInt: intOf('sdkInt'),
      legacyStorage: boolOf('legacyStorage'),
      requestsManage: boolOf('requestsManage'),
      requestsRead: boolOf('requestsRead'),
    );
    return DetectedEmulator(
      presetId: preset.id,
      variant: pkg,
      label: f['label'] is String ? f['label'] as String : preset.name,
      systems: preset.systems.keys.toList(),
      icon: f['icon'] is Uint8List ? f['icon'] as Uint8List : null,
      version: f['versionName'] is String ? f['versionName'] as String : null,
      dataDir: f['dataDir'] is String ? f['dataDir'] as String : null,
      requestsManage: facts.requestsManage,
      pathAccess: pathAccess(facts),
    );
  }
}
