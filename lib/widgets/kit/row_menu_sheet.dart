import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

/// One entry of a row's menu.
@immutable
class RowMenuItem {
  const RowMenuItem(this.label, this.onTap, {this.icon, this.subtitle, this.destructive = false});

  final String label;

  /// Runs after the sheet closes. Null: shown disabled.
  final VoidCallback? onTap;
  final IconData? icon;
  final String? subtitle;
  final bool destructive;
}

/// The menu of one row (Y on a pad, a long press on touch): the row's name,
/// then its actions. The first one has focus; B closes.
Future<void> showRowMenu(BuildContext context, {required String title, String? subtitle, required List<RowMenuItem> items}) async {
  final picked = await showModalBottomSheet<RowMenuItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => RowMenuSheet(title: title, subtitle: subtitle, items: items),
  );
  picked?.onTap?.call();
}

class RowMenuSheet extends StatelessWidget {
  const RowMenuSheet({super.key, required this.title, this.subtitle, required this.items});

  final String title;
  final String? subtitle;
  final List<RowMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final first = items.indexWhere((i) => i.onTap != null);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.row.copyWith(fontSize: t.size(16)), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (subtitle != null) Text(subtitle!, style: t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        for (var i = 0; i < items.length; i++)
          InkWell(
            autofocus: i == first,
            borderRadius: kitRowRadius(k),
            onTap: items[i].onTap == null ? null : () => Navigator.of(context).pop(items[i]),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Opacity(
                  opacity: items[i].onTap == null ? 0.45 : 1,
                  child: Row(children: [
                    if (items[i].icon != null) ...[Icon(items[i].icon, size: 20, color: items[i].destructive ? k.error : t.muted), const SizedBox(width: 12)],
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(items[i].label, style: t.row.copyWith(color: items[i].destructive ? k.error : null)),
                        if (items[i].subtitle != null) Text(items[i].subtitle!, style: t.subtitle),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Opens a row's menu from Y while the row (or anything in it) has focus,
/// and from a long press.
class RowMenuTarget extends StatelessWidget {
  const RowMenuTarget({super.key, required this.onMenu, required this.child});

  final VoidCallback onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
        actions: {
          ItemActionsIntent: CallbackAction<ItemActionsIntent>(onInvoke: (_) {
            onMenu();
            return null;
          }),
        },
        child: GestureDetector(onLongPress: onMenu, child: child),
      );
}
