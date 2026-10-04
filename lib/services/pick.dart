import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';

/// Android (SAF copies the whole file into cache) and handhelds (no native
/// dialog, not d-pad friendly) use the in-app [PathBrowser]; desktop and iOS
/// use the native picker.
bool get _useBrowser => Platform.isAndroid || Handheld.current;

Future<String> _startDir() async {
  if (Handheld.current) {
    final roots = handheldRoots();
    if (roots.isNotEmpty) return roots.keys.first;
  }
  return DirectoryService().getDownloadDir();
}

/// [extensions]: lowercase, no leading dot; null allows any file.
/// [useBrowser] only overrides the platform check in tests.
Future<String?> pickFile(
  BuildContext context, {
  required String title,
  List<String>? extensions,
  String? initialDir,
  @visibleForTesting bool? useBrowser,
}) async {
  if (useBrowser ?? _useBrowser) {
    final dir = initialDir ?? await _startDir();
    if (!context.mounted) return null;
    return PathBrowser.show(context, title: title, initialDir: dir, allowedExtensions: extensions);
  }
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: title,
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
    initialDirectory: initialDir,
  );
  return result?.files.firstOrNull?.path;
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
  return FilePicker.platform.getDirectoryPath(dialogTitle: title, initialDirectory: initialDir);
}
