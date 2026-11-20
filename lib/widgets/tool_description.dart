import 'package:flutter/material.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:url_launcher/url_launcher.dart';

/// The (i) in a screen's AppBar: "what is this / what it's for" opens in a
/// sheet, so the body starts with the controls.
class InfoButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? title;
  final Uri? learnMore;
  final String tooltip;

  /// Under the text: settings the screen keeps out of its body (Save Sync's
  /// hub). Built inside the sheet, so it can watch providers.
  final WidgetBuilder? extra;
  const InfoButton({super.key, required this.icon, required this.text, this.title, this.learnMore, this.tooltip = 'About this screen', this.extra});

  @override
  Widget build(BuildContext context) {
    return IconButton(icon: const Icon(Icons.info_outline), tooltip: tooltip, onPressed: () => _show(context));
  }

  Future<void> _show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(icon, size: 24, color: scheme.primary),
                if (title != null) ...[
                  const SizedBox(width: 12),
                  Expanded(child: Text(title!, style: theme.textTheme.titleMedium)),
                ],
              ]),
              const SizedBox(height: 12),
              Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              if (extra != null) ...[const SizedBox(height: 16), extra!(context)],
              const SizedBox(height: 16),
              // A focused button keeps the d-pad inside the sheet, so up/down
              // scroll a long text. The handheld has no browser for the link.
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (learnMore != null && !Handheld.current)
                  TextButton.icon(onPressed: () => openLink(learnMore!), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Learn more')),
                TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              ]),
            ],
          ),
        );
      },
    );
  }
}

/// Opens [uri] in the browser, as the About page does.
Future<void> openLink(Uri uri) async {
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}
