import 'package:flutter/material.dart';

/// What is behind the menus. Ported from Kitchentable's backdrop.
enum BackdropKind {
  flat('Flat'),
  paint('Paint'),
  aurora('Aurora'),
  drift('Drift'),
  dots('Dots'),
  image('Image');

  const BackdropKind(this.label);
  final String label;

  bool get animated => this == paint || this == aurora || this == drift;
}

/// The colour pairs offered in Style. Retro Toolbox is the app's own purple;
/// Flat with it was the one backdrop of every style before each had its own.
const backdropPresets = <String, (Color, Color)>{
  'Retro Toolbox': (Color(0xFF7C4DEF), Color(0xFF17102B)),
  'Pink on black': (Color(0xFFFF2E88), Color(0xFF07060A)),
  'Violet on black': (Color(0xFF7C5CFF), Color(0xFF06050B)),
  'Teal on black': (Color(0xFF00E0A4), Color(0xFF04080A)),
  'Amber on black': (Color(0xFFFFB03A), Color(0xFF0A0703)),
  'Felt green': (Color(0xFF2FA36B), Color(0xFF060D09)),
  'Ash': (Color(0xFF8A8A94), Color(0xFF0C0C0F)),
};

@immutable
class BackdropStyle {
  const BackdropStyle({this.kind = BackdropKind.flat, this.top = const Color(0xFF7C4DEF), this.bottom = const Color(0xFF17102B), this.imagePath});

  final BackdropKind kind;
  final Color top;
  final Color bottom;
  final String? imagePath;

  BackdropStyle copyWith({BackdropKind? kind, Color? top, Color? bottom, String? imagePath, bool clearImage = false}) => BackdropStyle(
        kind: kind ?? this.kind,
        top: top ?? this.top,
        bottom: bottom ?? this.bottom,
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      );

  Map<String, Object?> toJson() => {'kind': kind.name, 'top': top.toARGB32(), 'bottom': bottom.toARGB32(), if (imagePath != null) 'imagePath': imagePath};

  static BackdropStyle fromJson(Object? json) {
    if (json is! Map) return const BackdropStyle();
    final kind = BackdropKind.values.asNameMap()[json['kind']];
    final top = json['top'], bottom = json['bottom'], path = json['imagePath'];
    if (kind == null) return const BackdropStyle();
    return BackdropStyle(
      kind: kind,
      top: top is int ? Color(top) : const BackdropStyle().top,
      bottom: bottom is int ? Color(bottom) : const BackdropStyle().bottom,
      imagePath: path is String ? path : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackdropStyle && other.kind == kind && other.top == top && other.bottom == bottom && other.imagePath == imagePath;

  @override
  int get hashCode => Object.hash(kind, top, bottom, imagePath);
}

/// How cards look and are laid out. Classic is the app as it was.
enum CardStyle {
  classic('Classic'),
  vita('Vita'),
  threeDs('3DS'),
  wii('Wii'),
  switchStyle('Switch');

  const CardStyle(this.label);
  final String label;
}

@immutable
class AppStyle {
  const AppStyle({this.backdrop, this.cards = CardStyle.classic});

  /// The backdrop picked in Style; null until one is, and then the card
  /// style's own shows (StyleTokens.backdrop).
  final BackdropStyle? backdrop;
  final CardStyle cards;

  AppStyle copyWith({BackdropStyle? backdrop, CardStyle? cards}) => AppStyle(backdrop: backdrop ?? this.backdrop, cards: cards ?? this.cards);

  /// [backdrop] cleared, so the card style's own shows again.
  AppStyle withStyleBackdrop() => AppStyle(cards: cards);

  Map<String, Object?> toJson() => {if (backdrop != null) 'backdrop': backdrop!.toJson(), 'cards': cards.name};

  /// Saves from before the styles had backdrops of their own always carry
  /// one, and nearly always the old default because the card style was what
  /// got changed: that one reads as not picked, so the style's own shows.
  static AppStyle fromJson(Map<String, Object?> json) {
    final saved = json['backdrop'];
    final backdrop = saved == null ? null : BackdropStyle.fromJson(saved);
    return AppStyle(
      backdrop: backdrop == const BackdropStyle() ? null : backdrop,
      cards: CardStyle.values.asNameMap()[json['cards']] ?? CardStyle.classic,
    );
  }

  @override
  bool operator ==(Object other) => other is AppStyle && other.backdrop == backdrop && other.cards == cards;

  @override
  int get hashCode => Object.hash(backdrop, cards);
}
