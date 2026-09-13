import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

/// Whether the app has a token for this console. Reads only the settings,
/// which come from the vault.
bool consoleHasToken(AppSettings settings, String consoleId) => settings.consoleSettings[consoleId]?.authToken?.isNotEmpty ?? false;

/// The addons that served [games] and whose source on this console needs a
/// token. A game whose `sourceId` is no longer among the console's sources
/// does not block, and an open source is not tainted by a private neighbor.
List<String> addonsThatNeedToken(List<Game> games, List<ConsoleSource> sources) {
  final needing = <String>{};
  final seen = <String>{};
  for (final source in sources) {
    if (!seen.add(source.addonId)) continue;
    if (authNeedsToken(source.auth)) needing.add(source.addonId);
  }

  return [
    for (final addonId in {for (final game in games) game.sourceId})
      if (needing.contains(addonId)) addonId,
  ];
}
