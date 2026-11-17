import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Line icons drawn on a 24 grid with a 2 px round stroke in the current
/// colour, the set the settings sections use.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.paths, {super.key, this.size = 20, this.color});

  /// The SVG elements inside the 24x24 view box.
  final String paths;
  final double size;

  /// Null: the ambient icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
      'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">$paths</svg>',
      width: size,
      height: size,
      theme: SvgTheme(currentColor: c),
    );
  }
}

/// The section and sheet icons, as SVG elements for [SettingsIcon].
abstract final class SettingsIcons {
  static const library = '<path d="M4 5h4v14H4z"/><path d="M10 5h4v14h-4z"/><path d="M16.2 6.2l3.4-.9 3 12.6-3.4.9z"/>';
  static const downloads = '<path d="M12 4v11"/><path d="M8 11l4 4 4-4"/><path d="M5 19h14"/>';
  static const consoles =
      '<rect x="2" y="7" width="20" height="11" rx="5"/><path d="M7 10.5v4"/><path d="M5 12.5h4"/><path d="M15.5 12h.01"/><path d="M18 14h.01"/>';
  static const screens = '<rect x="5" y="2.5" width="14" height="8.5" rx="1.5"/><rect x="5" y="13" width="14" height="8.5" rx="1.5"/>';
  static const network = '<path d="M2 8.8a15 15 0 0 1 20 0"/><path d="M5 12.4a10 10 0 0 1 14 0"/><path d="M8.5 15.9a5 5 0 0 1 7 0"/><path d="M12 19.5h.01"/>';
  static const keys = '<circle cx="7.5" cy="15.5" r="4.5"/><path d="M10.7 12.3L20 3"/><path d="M16 7l3 3"/><path d="M14 9l2 2"/>';
  static const accounts = '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>';
  static const sports = '<circle cx="12" cy="12" r="9"/><path d="M12 7.5l4 2.9-1.5 4.7h-5L8 10.4z"/>';
  static const storage = '<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>';
  static const upload = '<path d="M4 20h16"/><path d="M12 4v11"/><path d="M8 8l4-4 4 4"/>';
  static const trash = '<path d="M4 7h16"/><path d="M6 7l1 13h10l1-13"/><path d="M9 7V4h6v3"/>';
  static const gear =
      '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>';
  static const check = '<path d="M5 12l5 5L20 7"/>';
  static const none = '';
  static const chevronRight = '<path d="M9 6l6 6-6 6"/>';
}
