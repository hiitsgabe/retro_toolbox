import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';

/// Nothing to show yet: one icon (one size everywhere), one line, at most one
/// action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon, this.glyph, required this.line, this.action});

  final IconData? icon;

  /// Drawn instead of [icon] in styles with pixel icons.
  final PixelGlyph? glyph;
  final String line;
  final KitAction? action;

  static const iconSize = 40.0;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final action = this.action;
    final glyph = this.glyph;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (t.k.pixelIcons && glyph != null)
            PixelIcon(glyph, size: iconSize, color: t.muted)
          else
            Icon(icon ?? Icons.inbox_outlined, size: iconSize, color: t.muted),
          const SizedBox(height: 10),
          Text(line, style: t.body.copyWith(color: t.muted, fontSize: t.size(14)), textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 14),
            if (action.icon == null)
              OutlinedButton(onPressed: action.onPressed, child: Text(action.label))
            else
              OutlinedButton.icon(onPressed: action.onPressed, icon: Icon(action.icon, size: 18), label: Text(action.label)),
          ],
        ]),
      ),
    );
  }
}
