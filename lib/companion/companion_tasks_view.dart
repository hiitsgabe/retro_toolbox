import 'package:flutter/material.dart';

/// One row of the tasks payload (see tasksPayload).
class CompanionTask {
  const CompanionTask({required this.title, required this.status, this.progress, this.state = 'active'});

  /// Throws on a row that is not the payload's shape.
  factory CompanionTask.fromJson(Map<String, dynamic> json) => CompanionTask(
        title: json['title'] as String,
        status: json['status'] as String? ?? '',
        progress: (json['progress'] as num?)?.toDouble(),
        state: json['state'] as String? ?? 'active',
      );

  final String title;
  final String status;

  /// 0..1, or null for no bar.
  final double? progress;

  /// 'active', 'queued', 'failed' or 'done'.
  final String state;
}

/// The Task Manager, read-only: what the main screen is downloading and
/// extracting, while it shows something other than a game.
class CompanionTasksView extends StatelessWidget {
  const CompanionTasksView({super.key, required this.tasks});

  final List<CompanionTask> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final top = MediaQuery.paddingOf(context).top;
    if (tasks.isEmpty) {
      return Center(
        child: Text('No tasks running', style: theme.textTheme.titleMedium?.copyWith(color: muted.withValues(alpha: 0.6))),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(40, top + 32, 40, 32),
      children: [
        Text('Tasks', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        for (final task in tasks) _TaskRow(task: task),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final CompanionTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = task.state == 'failed';
    final (icon, color) = switch (task.state) {
      'failed' => (Icons.error_outline_rounded, scheme.error),
      'queued' => (Icons.schedule_rounded, scheme.onSurfaceVariant),
      'done' => (Icons.check_circle_outline_rounded, scheme.onSurfaceVariant),
      _ => (Icons.downloading_rounded, scheme.primary),
    };
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  task.status,
                  style: theme.textTheme.bodyMedium?.copyWith(color: failed ? scheme.error : scheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.progress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: task.progress, borderRadius: BorderRadius.circular(2)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    // Finished rows stay for a moment; they matter least.
    return task.state == 'done' ? Opacity(opacity: 0.5, child: row) : row;
  }
}
