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

  /// Opens the system page where the user turns on all files access for
  /// [package] (Android 11+). False when it cannot.
  Future<bool> openAllFilesAccess(String package) async {
    try {
      return await _channel.invokeMethod<bool>('openAllFilesAccess', {'package': package}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Whether Retro Toolbox is the device's home app now: offered as one and
  /// the one picked, so false as soon as setHome(false) answers, even while
  /// Android still reports the role held. False when it cannot tell.
  Future<bool> isHomeHeld() async {
    try {
      return await _channel.invokeMethod<bool>('isHomeHeld') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// [on]: offers Retro Toolbox as a home app and asks Android to make it the
  /// one, answering once the user has; true when it is. Off: no longer
  /// offered, and false.
  Future<bool> setHome(bool on) async {
    try {
      return await _channel.invokeMethod<bool>('setHome', {'on': on}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// [onHome] runs on each Home press that reaches Retro Toolbox as the home
  /// app. Null stops it.
  void setHomeHandler(void Function()? onHome) => _channel.setMethodCallHandler(onHome == null
      ? null
      : (call) async {
          if (call.method == 'home') onHome();
        });

  /// The activity of [package] that a file is handed to when no recipe fits
  /// it: the one that answers ACTION_VIEW on a content URI, else its launcher
  /// activity. Null when it has neither, or when unsupported.
  Future<String?> viewActivity(String package) async {
    try {
      final reply = await _channel.invokeMethod<Object?>('viewActivity', {'package': package});
      return reply is String && reply.isNotEmpty ? reply : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
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
