import 'package:flutter/material.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// The batch confirmation sheet.
class BatchConfirmSheet extends StatelessWidget {
  final BatchPlan plan;
  final ValueChanged<BatchPlan> onConfirm;

  /// Receives the `gameId` of the row to drop from the batch.
  final ValueChanged<String> onRemove;

  const BatchConfirmSheet({
    super.key,
    required this.plan,
    required this.onConfirm,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = plan.picks.length;
    final header = '$n ${n == 1 ? 'game' : 'games'}, ${formatBytes(plan.totalBytes)}';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    header,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (plan.uncertainCount > 0)
                  Text(
                    '${plan.uncertainCount} uncertain',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final pick in plan.picks)
                  ListTile(
                    dense: true,
                    leading: pick.uncertain ? const Icon(Icons.help_outline, size: 20) : null,
                    title: Text(pick.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(pick.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      key: ValueKey('remove-${pick.gameId}'),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove from batch',
                      onPressed: () => onRemove(pick.gameId),
                    ),
                  ),
                if (plan.failures.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Not going to the queue',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final failure in plan.failures)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.cloud_off_rounded, size: 20, color: scheme.onSurfaceVariant),
                      title: Text(failure.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(failure.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  // With nothing picked there is nothing to queue, but the
                  // sheet stays open to show the failure reasons.
                  onPressed: plan.picks.isEmpty ? null : () => onConfirm(plan),
                  child: const Text('Download'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
