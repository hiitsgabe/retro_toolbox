import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/settings_icons.dart';

/// A sheet from the bottom for what a settings row opens: [title] and
/// [subtitle] over [builder]'s content, Cancel at the foot (B closes too).
/// Its content gets the sheet's own context, to pop it.
Future<T?> showSettingsSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
  String closeLabel = 'Cancel',
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) => _SettingsSheet(title: title, subtitle: subtitle, closeLabel: closeLabel, builder: builder),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.title, required this.subtitle, required this.closeLabel, required this.builder});

  final String title;
  final String? subtitle;
  final String closeLabel;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(subtitle!, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
              ),
            builder(context),
            SheetCloseButton(label: closeLabel),
          ],
        ),
      ),
    );
  }
}

/// One choice in a settings sheet: an icon and a label on a 60 px tile that
/// lights up under focus. [danger] in the error colour.
class SheetOption extends StatelessWidget {
  const SheetOption({super.key, required this.icon, required this.label, required this.onPressed, this.danger = false, this.autofocus = false});

  /// SVG elements for [SettingsIcon].
  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : scheme.onSurface;
    return SettingsTile(
      autofocus: autofocus,
      onTap: onPressed,
      color: Colors.transparent,
      focusedColor: scheme.surfaceContainerHighest,
      minHeight: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        SettingsIcon(icon, color: danger ? scheme.error : scheme.primary),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: fg))),
      ]),
    );
  }
}

/// The sheet's Cancel (or Done): plain text in the primary colour.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, this.label = 'Cancel'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsTile(
      onTap: () => Navigator.of(context).pop(),
      color: Colors.transparent,
      focusedColor: scheme.surfaceContainerHighest,
      minHeight: 52,
      padding: EdgeInsets.zero,
      child: Center(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.primary))),
    );
  }
}
