import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/app_state_model.dart';

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

/// How the games are laid out, apart from the card style: the style's own
/// layout, or one of Classic's views in the style's look.
enum GameLayout {
  styleDefault('Style default'),
  grid('Grid'),
  list('List'),
  coverFlow('Cover flow');

  const GameLayout(this.label);
  final String label;

  /// The header toggle's next pick: the three views in turn.
  GameLayout get next => switch (this) {
        grid => list,
        list => coverFlow,
        coverFlow || styleDefault => grid,
      };
}

@immutable
class AppStyle {
  const AppStyle({this.backdrop, this.cards = CardStyle.classic, this.gameLayout = GameLayout.styleDefault});

  /// The backdrop picked in Style; null until one is, and then the card
  /// style's own shows (StyleTokens.backdrop).
  final BackdropStyle? backdrop;
  final CardStyle cards;
  final GameLayout gameLayout;

  AppStyle copyWith({BackdropStyle? backdrop, CardStyle? cards, GameLayout? gameLayout}) =>
      AppStyle(backdrop: backdrop ?? this.backdrop, cards: cards ?? this.cards, gameLayout: gameLayout ?? this.gameLayout);

  /// [backdrop] cleared, so the card style's own shows again.
  AppStyle withStyleBackdrop() => AppStyle(cards: cards, gameLayout: gameLayout);

  /// The Classic view the games list shows, or null for the card style's
  /// own. Classic's own is [classicView], the header toggle's.
  ViewMode? gameView(ViewMode classicView) => switch (gameLayout) {
        GameLayout.styleDefault => cards == CardStyle.classic ? classicView : null,
        GameLayout.grid => ViewMode.grid,
        GameLayout.list => ViewMode.list,
        GameLayout.coverFlow => ViewMode.coverflow,
      };

  Map<String, Object?> toJson() => {if (backdrop != null) 'backdrop': backdrop!.toJson(), 'cards': cards.name, 'gameLayout': gameLayout.name};

  /// Saves from before the styles had backdrops of their own always carry
  /// one, and nearly always the old default because the card style was what
  /// got changed: that one reads as not picked, so the style's own shows.
  static AppStyle fromJson(Map<String, Object?> json) {
    final saved = json['backdrop'];
    final backdrop = saved == null ? null : BackdropStyle.fromJson(saved);
    return AppStyle(
      backdrop: backdrop == const BackdropStyle() ? null : backdrop,
      cards: CardStyle.values.asNameMap()[json['cards']] ?? CardStyle.classic,
      // Saves from before the setting have none: the style's own.
      gameLayout: GameLayout.values.asNameMap()[json['gameLayout']] ?? GameLayout.styleDefault,
    );
  }

  @override
  bool operator ==(Object other) => other is AppStyle && other.backdrop == backdrop && other.cards == cards && other.gameLayout == gameLayout;

  @override
  int get hashCode => Object.hash(backdrop, cards, gameLayout);
}
