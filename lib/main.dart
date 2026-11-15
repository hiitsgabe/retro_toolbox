import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
import 'package:retro_toolbox/providers/server_busy_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';
import 'package:retro_toolbox/screens/jdkv_server_screen.dart';
import 'package:retro_toolbox/services/extraction_service.dart';
import 'package:retro_toolbox/utils/focus_debug.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/utils/image_memory.dart';
import 'package:retro_toolbox/utils/server_mode.dart';

final serverProviders = <ProviderListenable>[
  fbiServerProvider,
  tinfoilServerProvider,
  fpkgiServerProvider,
  rtsServerProvider,
  jdkvServerProvider,
  ftpProvider,
];

void main() {
  ExtractionService.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  installFocusDebug();
  if (Platform.isAndroid || Handheld.current || ServerMode.current) capImageCache(PaintingBinding.instance.imageCache);
  // Tapping the JDKV notification asks the app to open the JDKV screen.
  FlutterForegroundTask.addTaskDataCallback((data) {
    if (data is Map && data['action'] == 'open_jdkv') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const JdkvServerScreen()),
      );
    }
  });
  final container = ProviderContainer();
  // Server mode: build the notifiers now so remembered servers come back without a UI.
  if (ServerMode.current) {
    for (final p in serverProviders) {
      container.read(p);
    }
    // A stale flag from a previous run must not block the watchdog.
    writeBusyFlag(false);
    container.listen(serverBusyProvider, (_, b) => writeBusyFlag(b), fireImmediately: true);
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const RetroToolboxApp(),
    ),
  );
}
