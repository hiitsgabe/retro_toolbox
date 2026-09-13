import 'package:flutter/material.dart';

/// The selection bar shown above the footer while a selection is active.
class SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDownload;

  const SelectionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              color: scheme.onPrimary,
              tooltip: 'Clear selection',
              onPressed: onClear,
            ),
            Expanded(
              child: Text(
                count == 1 ? '1 selected' : '$count selected',
                // Fixed-height bar: cap at one line so a large textScaler on a
                // narrow screen ellipsizes instead of clipping mid-word.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: onDownload,
                child: const Text('Download'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
