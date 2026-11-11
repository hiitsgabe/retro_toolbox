import 'dart:async';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// Under flutter test no plugin registers itself, so every test talks to this
// fallback. It is not exported.
// ignore: implementation_imports
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// Runs before every test file.
///
/// path_provider's method-channel fallback forwards getDownloadsDirectory to
/// `plugins.flutter.io/path_provider` only when the host is macOS; on any other
/// host it throws UnsupportedError before the channel is reached. Tests that
/// mock that channel therefore passed on a Mac and failed on Linux. This makes
/// the downloads call reach the channel on every host, as on macOS.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PathProviderPlatform.instance = _DownloadsOnEveryHost();
  await testMain();
}

class _DownloadsOnEveryHost extends MethodChannelPathProvider {
  @override
  Future<String?> getDownloadsPath() => methodChannel.invokeMethod<String>('getDownloadsDirectory');
}
