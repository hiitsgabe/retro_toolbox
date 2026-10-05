import 'dart:ffi' show Abi;
import 'dart:io';

/// Where the app runs as the Linux handheld port (flutter-pi). The launcher
/// (`linux/handheld/Retro Toolbox.sh`) exports `RETRO_TOOLBOX_HANDHELD=1`, and
/// `RETRO_TOOLBOX_FBDEV=1` when it falls back to the framebuffer.
class Handheld {
  static bool isLinuxHandheld({Map<String, String>? env, String? os, String? arch}) {
    final e = env ?? Platform.environment;
    final o = os ?? Platform.operatingSystem;
    final a = arch ?? (Abi.current() == Abi.linuxArm64 ? 'arm64' : 'other');
    return o == 'linux' && a == 'arm64' && e['RETRO_TOOLBOX_HANDHELD'] == '1';
  }

  static bool isFramebuffer({Map<String, String>? env}) => (env ?? Platform.environment)['RETRO_TOOLBOX_FBDEV'] == '1';

  /// Tests may override.
  static bool current = isLinuxHandheld();

  /// Tests may override.
  static bool framebuffer = current && isFramebuffer();
}
