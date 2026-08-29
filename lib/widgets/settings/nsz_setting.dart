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
        Row(
          children: [
            const Icon(Icons.compress),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NSZ Decompression', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  const Text('Decompress .nsz files to .nsp after download.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (v) => ref.read(settingsProvider.notifier).setNszDecompressEnabled(v),
            ),
          ],
        ),
        // Keys are only needed when decompression is on. Indent under the
        // header to read as a nested sub-item.
        if (enabled) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Row(
              children: [
                Icon(
                  hasKeys ? Icons.check_circle : Icons.vpn_key_outlined,
                  size: 20,
                  color: hasKeys ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Keys file', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        hasKeys ? p.basename(keysPath) : 'prod.keys / title.keys required',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasKeys ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _clearKeysFile(ref),
                  ),
                OutlinedButton(
                  onPressed: () => _pickKeysFile(ref),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(hasKeys ? 'Change' : 'Browse'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
