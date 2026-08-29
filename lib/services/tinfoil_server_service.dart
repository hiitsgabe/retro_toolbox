import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';

/// Serves a Tinfoil "shop": an index of the catalog's Switch games plus a
/// streaming proxy that injects source auth (IA S3 / bearer / cookie).
class TinfoilEntry {
  final Game game;
  final Console console;
  final String fileName;
  const TinfoilEntry({required this.game, required this.console, required this.fileName});
}

class TinfoilServerService {
  static const _switchFormats = {'.nsp', '.nsz', '.xci', '.xcz'};

  static bool isSwitchConsole(Console c) => c.fileFormat?.any((f) => _switchFormats.contains(f.toLowerCase())) ?? false;

  static String _fileName(Game game) {
    final title = game.title.split('/').last;
    return title.split('').map((ch) => RegExp(r"[a-zA-Z0-9 .\-_()\[\]']").hasMatch(ch) ? ch : '_').join();
  }

  /// Builds the Tinfoil index JSON and the route map keyed `<consoleId>/<idx>`.
  /// [hostPort] is the address the Switch reached us on (its Host header).
  static (Map<String, dynamic>, Map<String, TinfoilEntry>) buildIndex(Map<Console, List<Game>> gamesByConsole, String hostPort) {
    final files = <Map<String, dynamic>>[];
    final routes = <String, TinfoilEntry>{};
    gamesByConsole.forEach((console, games) {
      for (var i = 0; i < games.length; i++) {
        final entry = TinfoilEntry(game: games[i], console: console, fileName: _fileName(games[i]));
        final key = '${console.id}/$i';
        routes[key] = entry;
        files.add({
          'url': 'http://$hostPort/dl/$key/${Uri.encodeComponent(entry.fileName)}',
          'size': games[i].size,
        });
      }
    });
    return (
      {'files': files, 'success': 'Retro Toolbox — ${files.length} games'},
      routes,
    );
  }
}
