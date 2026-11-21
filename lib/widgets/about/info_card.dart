import 'package:retro_toolbox/utils/handheld.dart';
import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/kit/option_list.dart';
import 'package:url_launcher/url_launcher.dart';

/// A link row of About, inside a KitPanel: A or a tap copies [url] (not on
/// the handheld, which has no browser either), the open icon opens it.
class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? url;

  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.url,
  });

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return KitRow(
      onTap: Handheld.current ? null : onTap,
      child: Row(children: [
        AboutRowIcon(icon),
        const SizedBox(width: 12),
        Expanded(child: KitRowText(title: title, subtitle: subtitle)),
        if (url != null && !Handheld.current)
          IconButton(
            icon: Icon(Icons.open_in_new_rounded, size: 18, color: t.muted),
            tooltip: 'Open link',
            onPressed: () async {
              final uri = Uri.tryParse(url!);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        if (onTap != null && !Handheld.current) ...[const SizedBox(width: 4), Icon(Icons.copy_rounded, size: 18, color: t.muted)],
      ]),
    );
  }
}

/// The icon at the start of an About row: on a wash of the accent.
class AboutRowIcon extends StatelessWidget {
  const AboutRowIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final k = KitType.of(context).k;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: k.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 8).toDouble())),
      child: Icon(icon, size: 18, color: k.accent),
    );
  }
}
