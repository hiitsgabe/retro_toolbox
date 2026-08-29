import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';

class NszSetting extends ConsumerWidget {
  const NszSetting({super.key});

  Future<void> _pickKeysFile(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select prod.keys or title.keys',
      type: FileType.any,
      allowMultiple: false,
    );
    final src = result?.files.single.path;
    if (src == null) return;
    // Copy into app support: on Android the picker hands out a temp cache copy
    // that gets cleaned up; a stable path is also required by the Python process.
    final supportDir = await getApplicationSupportDirectory();
    final dest = File(p.join(supportDir.path, 'keys', p.basename(src)));
    await dest.parent.create(recursive: true);
    await File(src).copy(dest.path);
    await ref.read(settingsProvider.notifier).setNszKeysPath(dest.path);
  }

  Future<void> _clearKeysFile(WidgetRef ref) async {
    await ref.read(settingsProvider.notifier).setNszKeysPath('');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final enabled = settings.nszDecompressEnabled;
    final keysPath = settings.nszKeysPath;
    final hasKeys = keysPath != null && keysPath.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable NSZ Decompression'),
          subtitle: const Text(
            'Decompress .nsz files to .nsp after download.',
          ),
          secondary: const Icon(Icons.compress),
          value: enabled,
          onChanged: (v) => ref.read(settingsProvider.notifier).setNszDecompressEnabled(v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.key, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Keys File', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    hasKeys ? keysPath! : 'No file selected (prod.keys / title.keys)',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasKeys ? null : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (hasKeys)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Remove keys file',
                onPressed: () => _clearKeysFile(ref),
              ),
            OutlinedButton.icon(
              onPressed: () => _pickKeysFile(ref),
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Browse'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        if (hasKeys)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 14),
                SizedBox(width: 4),
                Text('Keys file set', style: TextStyle(fontSize: 12, color: Colors.green)),
              ],
            ),
          ),
      ],
    );
  }
}
