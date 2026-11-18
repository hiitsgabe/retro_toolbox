import 'package:flutter/material.dart';

/// What is behind the menus. Ported from Kitchentable's backdrop.
enum BackdropKind {
  flat('Flat'),
  paint('Paint'),
  aurora('Aurora'),
  drift('Drift'),
  image('Image');

  const BackdropKind(this.label);
  final String label;

  bool get animated => this == paint || this == aurora || this == drift;
}

/// The colour pairs offered in Style. Retro Toolbox is the app's own purple
/// and the default: Flat with it reads as the solid background of before.
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
  const AppStyle({this.backdrop = const BackdropStyle(), this.cards = CardStyle.classic});

  final BackdropStyle backdrop;
  final CardStyle cards;

  AppStyle copyWith({BackdropStyle? backdrop, CardStyle? cards}) => AppStyle(backdrop: backdrop ?? this.backdrop, cards: cards ?? this.cards);

  Map<String, Object?> toJson() => {'backdrop': backdrop.toJson(), 'cards': cards.name};

  static AppStyle fromJson(Map<String, Object?> json) => AppStyle(
        backdrop: BackdropStyle.fromJson(json['backdrop']),
        cards: CardStyle.values.asNameMap()[json['cards']] ?? CardStyle.classic,
      );

  @override
  bool operator ==(Object other) => other is AppStyle && other.backdrop == backdrop && other.cards == cards;

  @override
  int get hashCode => Object.hash(backdrop, cards);
}
