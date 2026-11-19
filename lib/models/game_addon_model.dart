import 'package:retro_toolbox/models/game_model.dart';

/// What a [GameAddon] adds to its game; each has its own catalog regex.
enum AddonKind { update, dlc, mod }

/// A downloadable update, DLC or mod of a catalog game (catalog keys
/// `update_regex`, `dlc_regex`, `mod_regex`).
class GameAddon {
  const GameAddon({this.kind = AddonKind.update, required this.label, required this.size, required this.url, required this.fileName});

  final AddonKind kind;

  /// What the feed calls it ("v262144", "2.2.1 [393216]", a DLC's name).
  final String label;
  final int size;
  final String url;

  /// What the downloaded file is called: the feed's name when it has one,
  /// else `<game> [<label>]<format>`.
  final String fileName;

  factory GameAddon.fromJson(Map<String, dynamic> json) => GameAddon(
        // Saved before DLC and mods: every addon was an update.
        kind: AddonKind.values.asNameMap()[json['kind']] ?? AddonKind.update,
        label: json['label'] as String? ?? '',
        size: json['size'] as int? ?? 0,
        url: json['url'] as String,
        fileName: json['fileName'] as String,
      );

  Map<String, dynamic> toJson() => {'kind': kind.name, 'label': label, 'size': size, 'url': url, 'fileName': fileName};

  /// This addon as a download of [game]'s console.
  Game toGame(Game game) =>
      Game(title: fileName, url: url, size: size, consoleId: game.consoleId, addonKind: kind, addonOf: game.title.replaceFirst(_format, ''));

  static final _format = RegExp(r'\.[A-Za-z0-9]{1,5}$');
}
