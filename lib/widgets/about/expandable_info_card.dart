import 'package:retro_toolbox/utils/handheld.dart';
import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/about/info_card.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/kit/option_list.dart';
import 'package:url_launcher/url_launcher.dart';

/// One entry under an expandable About row.
class InfoItem {
  final String title;
  final String subtitle;
  final String url;

  const InfoItem(this.title, this.subtitle, this.url);
}

/// An About row that opens its [items] in place (Authors, Credits).
class ExpandableInfoCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final List<InfoItem> items;
  final Function(String) onItemTap;
  final bool initExpanded;

  const ExpandableInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.items,
    required this.onItemTap,
    this.initExpanded = false,
  });

  @override
  State<ExpandableInfoCard> createState() => _ExpandableInfoCardState();
}

class _ExpandableInfoCardState extends State<ExpandableInfoCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final n = widget.items.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        expanded: _isExpanded,
        child: KitRow(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Row(children: [
            AboutRowIcon(widget.icon),
            const SizedBox(width: 12),
            Expanded(child: KitRowText(title: widget.title, subtitle: '$n ${n == 1 ? 'item' : 'items'}')),
            Icon(_isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 22, color: t.muted),
          ]),
        ),
      ),
      if (_isExpanded)
        ColoredBox(
          color: Colors.black.withValues(alpha: 0.12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final item in widget.items) ...[
              Divider(height: 1, thickness: 1, color: t.k.panelLine),
              KitRow(
                minHeight: 40,
                onTap: Handheld.current ? null : () => widget.onItemTap(item.url),
                child: Row(children: [
                  const SizedBox(width: 46),
                  Expanded(child: KitRowText(title: item.title, subtitle: item.subtitle)),
                  if (!Handheld.current) ...[
                    IconButton(
                      icon: Icon(Icons.open_in_new_rounded, size: 16, color: t.muted),
                      tooltip: 'Open link',
                      onPressed: () async {
                        final uri = Uri.tryParse(item.url);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.copy_rounded, size: 16, color: t.muted),
                      tooltip: 'Copy link',
                      onPressed: () => widget.onItemTap(item.url),
                    ),
                  ],
                ]),
              ),
            ],
          ]),
        ),
    ]);
  }
}
