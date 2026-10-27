import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';

/// Handhelds (no native dialog, not d-pad friendly) use the in-app
/// [PathBrowser] for folders; Android, desktop and iOS the system picker
/// (on Android a folder pick copies nothing, unlike a file pick).
bool get _useBrowser => Handheld.current;

Future<String> _startDir() async {
  if (Handheld.current) {
    final roots = handheldRoots();
    if (roots.isNotEmpty) return roots.keys.first;
  }
  return DirectoryService().getDownloadDir();
}

/// [extensions]: lowercase, no leading dot; null allows any file.
/// [androidNative]: on Android use the system picker (SAF) instead of the
/// in-app browser (the ROM pick: one file, so SAF's cache copy is fine).
/// [useBrowser] only overrides the platform check in tests.
Future<String?> pickFile(
  BuildContext context, {
  required String title,
  List<String>? extensions,
  String? initialDir,
  bool androidNative = false,
  @visibleForTesting bool? useBrowser,
}) async {
  final browser = useBrowser ?? (Handheld.current || (Platform.isAndroid && !androidNative));
  if (browser) {
    final dir = initialDir ?? await _startDir();
    if (!context.mounted) return null;
    return PathBrowser.show(context, title: title, initialDir: dir, allowedExtensions: extensions);
  }
  return _native(() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
      initialDirectory: initialDir,
    );
    return result?.files.firstOrNull?.path;
  });
}

Future<String?> pickDirectory(
  BuildContext context, {
  required String title,
  String? initialDir,
  @visibleForTesting bool? useBrowser,
}) async {
  if (useBrowser ?? _useBrowser) {
    final dir = initialDir ?? await _startDir();
    if (!context.mounted) return null;
    return PathBrowser.show(context, title: title, initialDir: dir, selectDirectory: true);
  }
  return _native(() => FilePicker.platform.getDirectoryPath(dialogTitle: title, initialDirectory: initialDir));
}

/// Where to save [fileName]. Browser mode has no save dialog, so it picks a
/// folder and joins the name (the caller writes the file; the folder may
/// already hold a file of that name). Desktop/iOS use the native save dialog;
/// [bytes] is only for iOS, which needs them up front.
Future<String?> pickSavePath(
  BuildContext context, {
  required String title,
  required String fileName,
  Uint8List? bytes,
  String? initialDir,
  @visibleForTesting bool? useBrowser,
}) async {
  final browser = useBrowser ?? _useBrowser;
  // Android's save dialog needs the bytes up front and hands back no path:
  // pick the folder with the system picker and join the name instead.
  if (browser || (useBrowser == null && Platform.isAndroid)) {
    final dir = await pickDirectory(context, title: title, initialDir: initialDir, useBrowser: browser);
    return dir == null ? null : p.join(dir, fileName);
  }
  return _native(() => FilePicker.platform.saveFile(dialogTitle: title, fileName: fileName, bytes: bytes, initialDirectory: initialDir));
}

/// Native pickers can throw (e.g. Linux without zenity); treat as a cancel.
Future<String?> _native(Future<String?> Function() pick) async {
  try {
    return await pick();
  } catch (e) {
    debugPrint('Native picker failed: $e');
    return null;
  }
}
