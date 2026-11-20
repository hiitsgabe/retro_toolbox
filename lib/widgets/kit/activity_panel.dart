import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

/// One line of a server's session log: what came or went, and when.
@immutable
class ActivityEntry {
  const ActivityEntry(this.title, {this.detail, this.time, this.tone = KitTone.neutral});

  final String title;
  final String? detail;
  final String? time;

  /// The dot before the line: success for a finished transfer, error for a
  /// failed one.
  final KitTone tone;
}

/// What a server is doing and has done this session: the live [count] and a
/// short log, newest first. Replaces snackbars the user may not have seen
/// while looking at the console.
class ActivityPanel extends StatelessWidget {
  const ActivityPanel({super.key, required this.count, this.entries = const [], this.title = 'Activity', this.countLabel, this.emptyText = 'Nothing yet this session'});

  final int count;
  final List<ActivityEntry> entries;
  final String title;

  /// "1 transfer"; null: the bare count.
  final String? countLabel;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return KitPanel(padding: const EdgeInsets.all(12), children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(title.toUpperCase(), style: t.label)),
          KitBadge(countLabel ?? '$count', tone: count > 0 ? KitTone.success : KitTone.neutral),
        ]),
        const SizedBox(height: 6),
        if (entries.isEmpty) Text(emptyText, key: const ValueKey('kit-activity-empty'), style: t.subtitle),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: kitToneColor(context, e.tone))),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, style: t.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (e.detail != null) Text(e.detail!, style: t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (e.time != null) ...[const SizedBox(width: 8), Text(e.time!, style: t.subtitle)],
            ]),
          ),
      ]),
    ]);
  }
}
