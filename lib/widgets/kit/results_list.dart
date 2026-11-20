import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

/// A result row: what it is, and its state as a badge (Keep, Delete, Rename,
/// Exists, Skipped, Failed).
@immutable
class ResultRow {
  const ResultRow({required this.id, required this.title, this.subtitle, this.badge, this.badgeTone = KitTone.neutral, this.selectable = true});

  final String id;
  final String title;
  final String? subtitle;
  final String? badge;
  final KitTone badgeTone;

  /// False: shown, never selected (an item that already exists).
  final bool selectable;
}

@immutable
class ResultGroup {
  const ResultGroup(this.title, this.rows);

  final String title;
  final List<ResultRow> rows;
}

/// What a list tool found (playlists to make, files to clean, shortcuts to
/// add): groups with a header each, one row per item, all in one scroll.
/// With [selected], A or a tap on a row marks it and Select (or the
/// header's All) marks every row, or none when all are; the count and the
/// action go in the screen's action bar.
class ResultsList extends StatelessWidget {
  const ResultsList({super.key, required this.groups, this.selected, this.onSelectionChanged, this.empty, this.shrinkWrap = false});

  final List<ResultGroup> groups;

  /// Null: rows are not selectable.
  final Set<String>? selected;
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// Shown when no group has rows.
  final Widget? empty;
  final bool shrinkWrap;

  Iterable<ResultRow> get _selectable => groups.expand((g) => g.rows).where((r) => r.selectable);

  /// Every selectable row of [rows] marked, or none when all of them are.
  Set<String> _toggleAll(Iterable<ResultRow> rows) {
    final ids = {for (final r in rows) if (r.selectable) r.id};
    final now = {...?selected};
    return now.containsAll(ids) ? (now..removeAll(ids)) : (now..addAll(ids));
  }

  void _toggle(ResultRow r) {
    final now = {...?selected};
    if (!now.remove(r.id)) now.add(r.id);
    onSelectionChanged?.call(now);
  }

  @override
  Widget build(BuildContext context) {
    final entries = <Object>[];
    for (final g in groups) {
      if (g.rows.isEmpty) continue;
      entries.add(g);
      entries.addAll(g.rows);
    }
    if (entries.isEmpty) return empty ?? const SizedBox.shrink();
    final selecting = selected != null;
    final list = ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        if (e is ResultGroup) {
          return _GroupHeader(
            group: e,
            selected: selected,
            onAll: selecting && onSelectionChanged != null ? () => onSelectionChanged!(_toggleAll(e.rows)) : null,
            first: i == 0,
          );
        }
        final r = e as ResultRow;
        return _Row(row: r, selected: selecting ? selected!.contains(r.id) : null, onTap: selecting && r.selectable && onSelectionChanged != null ? () => _toggle(r) : null);
      },
    );
    if (!selecting || onSelectionChanged == null) return list;
    return Actions(
      actions: {
        OptionsIntent: CallbackAction<OptionsIntent>(onInvoke: (_) {
          onSelectionChanged!(_toggleAll(_selectable));
          return null;
        }),
      },
      child: list,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.selected, required this.onAll, required this.first});

  final ResultGroup group;
  final Set<String>? selected;
  final VoidCallback? onAll;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final selectable = group.rows.where((r) => r.selectable).toList();
    final marked = selected == null ? 0 : selectable.where((r) => selected!.contains(r.id)).length;
    final all = selectable.isNotEmpty && marked == selectable.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, first ? 2 : 12, 2, 4),
      child: Row(children: [
        Expanded(child: Text(group.title.toUpperCase(), style: t.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (selected != null) Text('$marked of ${selectable.length}', key: ValueKey('kit-group-count-${group.title}'), style: t.subtitle),
        if (onAll != null && selectable.isNotEmpty)
          // Not a focus stop: Select does it from any row.
          ExcludeFocus(
            child: TextButton(
              onPressed: onAll,
              style: TextButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(all ? 'None' : 'All'),
            ),
          ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.selected, required this.onTap});

  final ResultRow row;

  /// Null: the list does not select.
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final selected = this.selected;
    final subtitle = row.subtitle;
    final badge = row.badge;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: k.panel,
        shape: RoundedRectangleBorder(borderRadius: kitRowRadius(k), side: BorderSide(color: selected == true ? k.accent.withValues(alpha: 0.6) : k.panelLine)),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          selected: selected,
          child: InkWell(
            borderRadius: kitRowRadius(k),
            onTap: onTap,
            canRequestFocus: onTap != null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  if (selected != null) ...[_Check(on: selected, enabled: row.selectable), const SizedBox(width: 12)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(row.title, style: t.row, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (subtitle != null) Text(subtitle, style: t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  if (badge != null) ...[const SizedBox(width: 10), KitBadge(badge, tone: row.badgeTone)],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.on, required this.enabled});

  final bool on;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: on ? k.accent : Colors.transparent,
          border: on ? null : Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
          borderRadius: BorderRadius.circular(k.buttonRadius.clamp(2, 5).toDouble()),
        ),
        child: on ? Icon(Icons.check, size: 16, color: k.onAccent) : null,
      ),
    );
  }
}
