import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

enum WorkState { queued, running, done, failed }

/// One item of a tool's work: queued, running (with [progress] 0 to 1, null
/// when unknown), done or failed.
@immutable
class WorkItem {
  const WorkItem(this.name, {this.state = WorkState.running, this.progress, this.note});

  final String name;
  final WorkState state;
  final double? progress;

  /// Replaces the state word: "3 of 7 files".
  final String? note;
}

/// An item a finished run skipped or failed, and why.
@immutable
class Problem {
  const Problem(this.name, this.reason, {this.failed = false});

  final String name;
  final String reason;

  /// Failed; otherwise skipped.
  final bool failed;
}

enum StatusKind { hidden, missingRequirement, working, done, error }

/// The one place a tool says how it is going: nothing yet, a missing
/// requirement (with its fix), the work in progress, the result (with what
/// was skipped or failed, and why) or an error (one line, details on demand).
/// The form around it stays visible in every state.
class StatusPanel extends StatelessWidget {
  const StatusPanel.hidden({super.key})
      : kind = StatusKind.hidden,
        text = '',
        detail = null,
        actionLabel = null,
        onAction = null,
        linkLabel = null,
        onLink = null,
        items = const [],
        problems = const [],
        dense = null;

  /// [title]: "chdman not found". [actionLabel] runs the fix ("Locate
  /// chdman"); [linkLabel] opens where to read more ("Settings > Keys").
  const StatusPanel.missingRequirement({
    super.key,
    required String title,
    this.detail,
    required String this.actionLabel,
    required this.onAction,
    this.linkLabel,
    this.onLink,
  })  : kind = StatusKind.missingRequirement,
        text = title,
        items = const [],
        problems = const [],
        dense = null;

  /// [items] in order: the first running one gets the bar. [dense] (null:
  /// in portrait) shows only it and how many wait.
  const StatusPanel.working({super.key, required this.items, this.dense})
      : kind = StatusKind.working,
        text = '',
        detail = null,
        actionLabel = null,
        onAction = null,
        linkLabel = null,
        onLink = null,
        problems = const [];

  /// [actionLabel]: what to do next with the result ("Extract here").
  const StatusPanel.done({super.key, required String summary, this.problems = const [], this.actionLabel, this.onAction})
      : kind = StatusKind.done,
        text = summary,
        detail = null,
        linkLabel = null,
        onLink = null,
        items = const [],
        dense = null;

  /// [line]: what went wrong, for a person. [details]: the raw error, shown
  /// on Details.
  const StatusPanel.error({super.key, required String line, String? details})
      : kind = StatusKind.error,
        text = line,
        detail = details,
        actionLabel = null,
        onAction = null,
        linkLabel = null,
        onLink = null,
        items = const [],
        problems = const [],
        dense = null;

  final StatusKind kind;
  final String text;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? linkLabel;
  final VoidCallback? onLink;
  final List<WorkItem> items;
  final List<Problem> problems;
  final bool? dense;

  bool get isHidden => kind == StatusKind.hidden || (kind == StatusKind.working && items.isEmpty);

  @override
  Widget build(BuildContext context) {
    if (isHidden) return const SizedBox.shrink();
    final t = KitType.of(context);
    final k = t.k;
    final Widget body = switch (kind) {
      StatusKind.missingRequirement => _missing(context, t),
      StatusKind.working => _working(context, t),
      StatusKind.done => _done(context, t),
      StatusKind.error => _error(context, t),
      StatusKind.hidden => const SizedBox.shrink(),
    };
    return KitPanel(
      key: ValueKey('kit-status-${kind.name}'),
      edge: switch (kind) {
        StatusKind.missingRequirement => k.warning.withValues(alpha: 0.4),
        StatusKind.error => k.error.withValues(alpha: 0.4),
        _ => null,
      },
      padding: const EdgeInsets.all(12),
      children: [body],
    );
  }

  Widget _missing(BuildContext context, KitType t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.extension_outlined, size: 18, color: t.k.warning),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: t.row)),
      ]),
      if (detail != null) ...[const SizedBox(height: 4), Text(detail!, style: t.subtitle)],
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton(
          onPressed: onAction,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: Text(actionLabel!),
        ),
        if (linkLabel != null)
          TextButton(
            onPressed: onLink,
            style: TextButton.styleFrom(minimumSize: const Size(0, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(linkLabel!),
          ),
      ]),
    ]);
  }

  static String _word(WorkItem i) =>
      i.note ??
      switch (i.state) {
        WorkState.queued => 'queued',
        WorkState.running => i.progress == null ? 'working' : '${(i.progress! * 100).round()}%',
        WorkState.done => 'done',
        WorkState.failed => 'failed',
      };

  Widget _working(BuildContext context, KitType t) {
    final dense = this.dense ?? DeviceClass.of(context) == DeviceClass.portrait;
    final lead = items.firstWhere((i) => i.state == WorkState.running, orElse: () => items.first);
    final rest = [for (final i in items) if (!identical(i, lead)) i];
    final waiting = rest.where((i) => i.state == WorkState.queued).length;
    final leadWord = dense && waiting > 0 ? '${_word(lead)} · +$waiting queued' : _word(lead);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Text(lead.name, style: t.row, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(leadWord, style: t.subtitle.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
      if (lead.state == WorkState.running) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(key: const ValueKey('kit-status-bar'), value: lead.progress, minHeight: 5),
        ),
      ],
      if (!dense)
        for (final i in rest)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(child: Text(i.name, style: t.subtitle.copyWith(color: t.ink.withValues(alpha: 0.75)), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(_word(i),
                  style: t.subtitle.copyWith(
                    color: switch (i.state) {
                      WorkState.done => t.k.success,
                      WorkState.failed => t.k.error,
                      _ => t.muted,
                    },
                  )),
            ]),
          ),
    ]);
  }

  Widget _done(BuildContext context, KitType t) {
    final failed = problems.any((p) => p.failed);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(failed ? Icons.error_outline : Icons.check_circle_outline, size: 18, color: failed ? t.k.warning : t.k.success),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: t.row)),
      ]),
      if (actionLabel != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('kit-status-action'),
              onPressed: onAction,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(actionLabel!),
            ),
          ),
        ),
      for (final p in problems)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KitBadge(p.failed ? 'Failed' : 'Skipped', tone: p.failed ? KitTone.error : KitTone.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: t.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(p.reason, style: t.subtitle),
              ]),
            ),
          ]),
        ),
    ]);
  }

  Widget _error(BuildContext context, KitType t) {
    final details = detail;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.error_outline, size: 18, color: t.k.error)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: t.row)),
      if (details != null && details.isNotEmpty)
        TextButton(
          onPressed: () => _showDetails(context, text, details),
          style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: const Text('Details'),
        ),
    ]);
  }
}

Future<void> _showDetails(BuildContext context, String line, String details) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) {
      final t = KitType.of(context);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(line, style: t.row),
          const SizedBox(height: 10),
          SelectableText(details, key: const ValueKey('kit-status-details'), style: t.mono(12).copyWith(color: t.muted)),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))),
        ]),
      );
    },
  );
}
