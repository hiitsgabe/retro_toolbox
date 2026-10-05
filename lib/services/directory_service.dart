import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:path/path.dart' as path;

class DirectoryService {
  Future<String> getDownloadDir() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDir = prefs.getString('downloadDir');

    if (savedDir != null && savedDir.isNotEmpty) {
      final dir = Directory(savedDir);
      if (await dir.exists()) {
        return savedDir;
      }
    }

    if (Platform.isAndroid) {
      if (await Permission.storage.status.isGranted) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          return externalDir.path;
        }
      }
    }

    final downloadDir = await getDownloadsDirectory();
    if (downloadDir != null) {
      return downloadDir.path;
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    return appDocDir.path;
  }

  Future<void> saveDownloadDirectory(String dir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('downloadDir', dir);
  }

  static Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        debugPrint('Deleted file: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to delete file: $e');
      return false;
    }
  }

  static bool isCompressedFile(String filePath) {
    Set<String> extensions = {'.zip'};
    if (!Platform.isAndroid) {
      extensions.addAll({'.tar', '.gz', '.tar.gz', '.tgz', '.bz2', '.tar.bz2', '.tbz', '.xz', '.tar.xz', '.txz'});
    }
    return extensions.contains(path.extension(filePath).toLowerCase()) || extensions.contains(path.extension(filePath, 2).toLowerCase());
  }

  static Future<int> getFreeSpace(String dirPath) async => (await getFreeSpaceOrNull(dirPath)) ?? 0;

  /// Free bytes at [dirPath], or null when it can't be told (`df` failed or
  /// printed something unreadable) so callers can tell "unknown" from "0".
  static Future<int?> getFreeSpaceOrNull(String dirPath) async {
    // disk_space_2 is a GTK plugin: flutter-pi (handheld Linux) doesn't load
    // it, so Linux reads `df` too. -P keeps each filesystem on one line.
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        final result = await Process.run('df', ['-Pk', dirPath]);
        return result.exitCode != 0 ? null : parseDfAvailable(result.stdout.toString());
      } catch (_) {
        return null;
      }
    }

    final freeInMb = (await DiskSpace.getFreeDiskSpaceForPath(dirPath))?.toInt();
    return freeInMb == null ? null : freeInMb * 1024 * 1024;
  }

  /// Available bytes from `df -Pk` output; null when it can't be read.
  static int? parseDfAvailable(String output) {
    final lines = output.trim().split('\n');
    if (lines.length < 2) return null;
    final parts = lines[1].split(RegExp(r"\s+"));
    if (parts.length < 4) return null;
    final availKb = int.tryParse(parts[3]);
    return availKb == null ? null : availKb * 1024;
  }
}
