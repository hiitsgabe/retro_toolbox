import 'package:flutter/material.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// A small file with this device's address in it that has to land on the
/// console's SD card (FPKGi's config.json, JDKV's webdav.json): its name,
/// where it goes on the console, Save and Copy, and a warning when the copy
/// on the console carries an old address.
class ConfigFileSlot extends StatelessWidget {
  const ConfigFileSlot({
    super.key,
    required this.fileName,
    required this.destination,
    required this.onSave,
    this.onCopy,
    this.saveLabel = 'Save file',
    this.stale = false,
    this.staleText = 'The saved file has an old address. Save it again.',
  });

  final String fileName;

  /// On the console: "sd:/switch/JKSV/webdav.json".
  final String destination;
  final VoidCallback? onSave;

  /// Null, or on the Linux handheld (no clipboard): no Copy.
  final VoidCallback? onCopy;
  final String saveLabel;
  final bool stale;
  final String staleText;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final copy = onCopy != null && !Handheld.current;
    return KitPanel(padding: const EdgeInsets.all(12), edge: stale ? k.warning.withValues(alpha: 0.4) : null, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          k.pixelIcons ? PixelIcon(PixelIcons.file, size: 20, color: k.accent) : Icon(Icons.description_outlined, size: 20, color: k.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fileName, style: t.mono(14)),
              Text('Goes to $destination', style: t.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        if (stale) ...[
          const SizedBox(height: 8),
          Row(key: const ValueKey('kit-config-stale'), crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: k.warning),
            const SizedBox(width: 6),
            Expanded(child: Text(staleText, style: t.subtitle.copyWith(color: k.warning))),
          ]),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 6, children: [
          FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(saveLabel),
          ),
          if (copy)
            OutlinedButton(
              onPressed: onCopy,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Copy'),
            ),
        ]),
      ]),
    ]);
  }
}
