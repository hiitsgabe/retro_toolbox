import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/app.dart';
import 'package:roms_downloader/screens/jdkv_server_screen.dart';
import 'package:roms_downloader/services/extraction_service.dart';

void main() {
  ExtractionService.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  // Tapping the JDKV notification asks the app to open the JDKV screen.
  FlutterForegroundTask.addTaskDataCallback((data) {
    if (data is Map && data['action'] == 'open_jdkv') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const JdkvServerScreen()),
      );
    }
  });
  runApp(
    const ProviderScope(
      child: RomsDownloaderApp(),
    ),
  );
}
