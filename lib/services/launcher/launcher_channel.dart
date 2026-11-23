import 'package:flutter/services.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';

/// `retro_toolbox/launcher`. Every method answers; a missing plugin (desktop,
/// tests) or a native error never reaches the caller as an exception.
class LauncherChannel {
  const LauncherChannel([this._channel = const MethodChannel('retro_toolbox/launcher')]);

  final MethodChannel _channel;

  /// Facts for every installed variant whose activity is exported, for
  /// [presets] as `[{id, packages, activity}]`. Empty when unsupported.
  Future<List<Map<String, Object?>>> detect(List<Map<String, Object?>> presets) async {
    try {
      final reply = await _channel.invokeListMethod<Object?>('detect', {'presets': presets});
      return [for (final e in reply ?? const []) if (e is Map) e.cast<String, Object?>()];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<LaunchResult> launch(Map<String, Object?> args) async {
    try {
      return LaunchResult.fromReply(await _channel.invokeMethod<Object?>('launch', args));
    } on MissingPluginException {
      return const LaunchResult(LaunchCode.unsupported);
    } on PlatformException catch (e) {
      return LaunchResult(LaunchCode.refused, message: e.message);
    }
  }

  /// Opens [package] the way its launcher icon does. False when it cannot.
  Future<bool> openApp(String package) async {
    try {
      return await _channel.invokeMethod<bool>('openApp', {'package': package}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
