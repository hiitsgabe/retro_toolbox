import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/kit/slot.dart' show pathSeparator;

/// One folder of the trail: tapping it goes there.
@immutable
class Crumb {
  const Crumb(this.label, [this.onTap]);

  final String label;
  final VoidCallback? onTap;
}

/// The top of a browser (File Explorer, SMB, FTP client): the folder trail,
/// the current folder last and always in view, then the actions by name
/// ("New folder", "Upload here"), then [menu] as one icon for the rest (the
/// view, Refresh). The trail is for touch; on a pad B goes up. On a phone the
/// actions take a row under the trail, so the trail keeps the width.
class BrowserBar extends StatelessWidget {
  const BrowserBar({super.key, required this.crumbs, this.actions = const [], this.menu, this.menuTooltip = 'More'});

  final List<Crumb> crumbs;
  final List<KitAction> actions;
  final VoidCallback? menu;
  final String menuTooltip;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final trail = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final c = crumbs[i];
      final last = i == crumbs.length - 1;
      if (i > 0) trail.add(Text(pathSeparator.trim(), style: t.subtitle));
      final text = Text(c.label, style: last ? t.row : t.subtitle.copyWith(fontSize: t.size(13)), maxLines: 1);
      trail.add(c.onTap == null || last
          ? Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: text)
          : InkWell(
              canRequestFocus: false,
              onTap: c.onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: text),
            ));
    }
    final trailView = LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        key: const ValueKey('kit-crumbs'),
        scrollDirection: Axis.horizontal,
        // The current folder is at the end: start scrolled there. A trail
        // that fits still starts at the left.
        reverse: true,
        child: ConstrainedBox(constraints: BoxConstraints(minWidth: box.maxWidth), child: Row(children: trail)),
      ),
    );
    final buttons = [
      for (final a in actions)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: a.icon == null
              ? TextButton(onPressed: a.onPressed, child: Text(a.label))
              : TextButton.icon(onPressed: a.onPressed, icon: Icon(a.icon, size: 18), label: Text(a.label)),
        ),
    ];
    final menuButton = menu == null
        ? null
        : IconButton(onPressed: menu, tooltip: menuTooltip, icon: const Icon(Icons.more_vert, size: 20), visualDensity: VisualDensity.compact);
    if (DeviceClass.of(context) == DeviceClass.portrait && actions.isNotEmpty) {
      return KitPanel(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), divided: false, children: [
        Row(children: [Expanded(child: trailView), if (menuButton != null) menuButton]),
        Row(children: [
          for (final b in buttons) Flexible(child: b),
        ]),
      ]);
    }
    return KitPanel(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), children: [
      Row(children: [Expanded(child: trailView), ...buttons, if (menuButton != null) menuButton]),
    ]);
  }
}
