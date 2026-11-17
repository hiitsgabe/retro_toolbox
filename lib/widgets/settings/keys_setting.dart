import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/key_files.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';
import 'package:retro_toolbox/widgets/settings/settings_icons.dart';
import 'package:retro_toolbox/widgets/settings/settings_sheet.dart';

/// The sheet a key row opens: Choose file (another one when set), Remove.
Future<void> showKeyFileSheet(BuildContext context, WidgetRef ref, KeyFile key) {
  return showSettingsSheet<void>(
    context,
    title: key.title,
    subtitle: key.subtitle,
    builder: (sheet) => Consumer(builder: (sheet, ref, _) {
      final path = key.pathIn(ref.watch(settingsProvider));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        SheetOption(
          icon: SettingsIcons.upload,
          label: path == null ? 'Choose file' : 'Choose another file',
          autofocus: true,
          onPressed: () async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            Navigator.of(sheet).pop();
            try {
              await chooseKeyFile(context, ref, key);
            } catch (e) {
              messenger?.showSnackBar(SnackBar(content: Text('Could not copy the file: $e')));
            }
          },
        ),
        if (path != null)
          SheetOption(
            icon: SettingsIcons.trash,
            label: 'Remove ${p.basename(path)}',
            danger: true,
            onPressed: () async {
              Navigator.of(sheet).pop();
              await removeKeyFile(ref, key);
            },
          ),
      ]);
    }),
  );
}

/// One key in Settings > Keys: its file's name or "Not set".
class KeyFileRow extends ConsumerWidget {
  const KeyFileRow({super.key, required this.file});

  final KeyFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = file.pathIn(ref.watch(settingsProvider));
    return SettingsValueRow(
      key: ValueKey('key ${file.name}'),
      title: file.title,
      subtitle: file.subtitle,
      value: path == null ? 'Not set' : p.basename(path),
      onTap: () => showKeyFileSheet(context, ref, file),
    );
  }
}
