import 'package:retro_toolbox/models/game_model.dart';

/// A downloadable update of a catalog game (catalog key `update_regex`).
class GameUpdate {
  const GameUpdate({required this.label, required this.size, required this.url, required this.fileName});

  /// The version as the feed names it ("v262144", "2.2.1 [393216]").
  final String label;
  final int size;
  final String url;

  /// What the downloaded file is called: `<game> [<label>]<format>`.
  final String fileName;

  factory GameUpdate.fromJson(Map<String, dynamic> json) => GameUpdate(
        label: json['label'] as String? ?? '',
        size: json['size'] as int? ?? 0,
        url: json['url'] as String,
        fileName: json['fileName'] as String,
      );

  Map<String, dynamic> toJson() => {'label': label, 'size': size, 'url': url, 'fileName': fileName};

  /// This update as a download of [game]'s console.
  Game toGame(Game game) => Game(title: fileName, url: url, size: size, consoleId: game.consoleId, isUpdate: true);
}
