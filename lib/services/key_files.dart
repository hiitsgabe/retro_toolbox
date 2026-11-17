import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/pick.dart';

/// A key or BIOS file a converter needs, from the user's own console. One
/// place picks, copies and stores each: Settings > Keys and the converter
/// screens all go through [chooseKeyFile] and [removeKeyFile].
enum KeyFile {
  switchKeys(
    title: 'Switch keys',
    subtitle: 'prod.keys or title.keys, for NSZ to NSP',
    header: 'Nintendo Switch',
    short: 'Switch keys',
    pickTitle: 'Select prod.keys or title.keys',
  ),
  boot9(
    title: 'boot9.bin or aes_keys.txt',
    subtitle: 'For encrypted 3DS dumps to CIA',
    header: 'Nintendo 3DS',
    short: 'boot9',
    pickTitle: 'Select boot9.bin or aes_keys.txt',
  );

  const KeyFile({required this.title, required this.subtitle, required this.header, required this.short, required this.pickTitle});

  final String title;
  final String subtitle;

  /// The console it belongs to, a header in Keys.
  final String header;

  /// How a summary line names it.
  final String short;
  final String pickTitle;

  /// The stored copy's path, or null when none is set.
  String? pathIn(AppSettings s) {
    final path = switch (this) {
      KeyFile.switchKeys => s.nszKeysPath,
      KeyFile.boot9 => s.boot9Path,
    };
    return path == null || path.isEmpty ? null : path;
  }

  Future<void> _store(SettingsNotifier n, String path) => switch (this) {
        KeyFile.switchKeys => n.setNszKeysPath(path),
        KeyFile.boot9 => n.setBoot9Path(path),
      };
}

/// Test seams: the file picker and the folder copies go to.
@visibleForTesting
Future<String?> Function(BuildContext context, String title)? debugPickKeyFile;
@visibleForTesting
Future<Directory> Function()? debugKeysParent;

/// Copies [src] into the app's own `keys` folder under [parent] and returns
/// the copy. On Android the picker hands out a temporary copy that gets
/// cleaned up, and the converters need a path that stays.
Future<File> copyKeyIntoApp(String src, Directory parent) async {
  final dest = File(p.join(parent.path, 'keys', p.basename(src)));
  await dest.parent.create(recursive: true);
  return File(src).copy(dest.path);
}

/// Picks [key]'s file, copies it into the app and stores the copy's path.
/// Null when the pick was cancelled; throws when the copy fails.
Future<String?> chooseKeyFile(BuildContext context, WidgetRef ref, KeyFile key) async {
  final src = await (debugPickKeyFile ?? (c, t) => pickFile(c, title: t))(context, key.pickTitle);
  if (src == null) return null;
  final parent = await (debugKeysParent ?? getApplicationSupportDirectory)();
  final copy = await copyKeyIntoApp(src, parent);
  await key._store(ref.read(settingsProvider.notifier), copy.path);
  return copy.path;
}

/// Forgets [key]'s file. The copy stays, so choosing it again is instant.
Future<void> removeKeyFile(WidgetRef ref, KeyFile key) => key._store(ref.read(settingsProvider.notifier), '');
