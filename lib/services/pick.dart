import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
/// in-app browser (the ROM pick; a file with no path on disk gets copied).
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
  if (Platform.isAndroid) return _androidPick(dir: false, initialDir: initialDir);
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
  if (Platform.isAndroid) return _androidPick(dir: true, initialDir: initialDir);
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

const _pickChannel = MethodChannel('retro_toolbox/pick');
const _externalStorage = 'com.android.externalstorage.documents';

/// Android's system picker through MainActivity: file_picker ignores
/// initialDirectory there (saves aside), so it opened wherever it last was.
/// Starts at [initialDir], else the download folder, else internal storage.
Future<String?> _androidPick({required bool dir, String? initialDir}) => _native(() async {
  final primary = await _primaryRoot();
  final start = initialDir ?? await DirectoryService().getDownloadDir();
  final r = await _pickChannel.invokeMapMethod<String, String?>('pick', {'dir': dir, 'initialDocId': initialDocId(start, primary)});
  if (r == null) return null;
  final path = docPath(r['authority'], r['docId'], primary);
  // A file with no path on disk (Drive, media): copy it, as file_picker did.
  if (path != null || dir) return path;
  return _pickChannel.invokeMethod<String>('copy', {'uri': r['uri']});
});

/// Internal storage root (`/storage/emulated/<user>`), from the app's own
/// external folder (`<root>/Android/data/<package>/files`).
Future<String> _primaryRoot() async {
  final own = (await getExternalStorageDirectory())?.path;
  final i = own?.indexOf('/Android/') ?? -1;
  return i > 0 ? own!.substring(0, i) : '/storage/emulated/0';
}

/// SAF document id of [path] (for EXTRA_INITIAL_URI): `primary:<rel>` under
/// internal storage, `<uuid>:<rel>` on an SD card / USB volume. Anything else
/// (app-private folders, which the picker can't show) starts at internal
/// storage.
@visibleForTesting
String initialDocId(String? path, String primary) {
  if (path == null) return 'primary:';
  final n = p.posix.normalize(path);
  if (n == primary || p.posix.isWithin(primary, n)) {
    final rel = n == primary ? '' : p.posix.relative(n, from: primary);
    // Android 11+ hides Android/data and Android/obb from the picker.
    return p.posix.split(rel).firstOrNull == 'Android' ? 'primary:' : 'primary:$rel';
  }
  final m = RegExp(r'^/storage/([^/]+)(?:/(.*))?$').firstMatch(n);
  if (m != null && m[1] != 'emulated' && m[1] != 'self') return '${m[1]}:${m[2] ?? ''}';
  return 'primary:';
}

/// Real path of a picked document; null when it has none (Drive, media...).
@visibleForTesting
String? docPath(String? authority, String? docId, String primary) {
  if (docId == null) return null;
  // Downloads on older Androids hands out raw:<path>.
  if (docId.startsWith('raw:')) return docId.substring(4);
  final i = docId.indexOf(':');
  if (authority != _externalStorage || i < 0) return null;
  final vol = docId.substring(0, i), rel = docId.substring(i + 1);
  final root = switch (vol) {
    'primary' => primary,
    'home' => '$primary/Documents',
    _ => '/storage/$vol',
  };
  return rel.isEmpty ? root : p.posix.join(root, rel);
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
