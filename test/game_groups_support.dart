import 'dart:io';

import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/utils/title_metadata_parser.dart';

/// A PS1 file as the Internet Archive lists it: the No-Intro name plus .zip,
/// with the metadata the catalog parses.
Game psxGame(String name, {int? launchboxId, int size = 100}) {
  final title = '$name.zip';
  return Game(
    title: title,
    url: 'https://archive.org/download/psx/${Uri.encodeComponent(title)}',
    size: size,
    consoleId: 'psx',
    metadata: TitleMetadataParser.parseRomTitle(title),
    details: launchboxId == null ? null : GameDetails(launchboxId: launchboxId),
  );
}

List<String> _names() => [
      for (final line in File('test/fixtures/psx_group_names.txt').readAsLinesSync())
        if (line.isNotEmpty) line,
    ];

/// The fixture's files whose base title (the name before " (") is one of
/// [bases], in file order.
List<Game> psxGames(List<String> bases, {int? launchboxId}) => [
      for (final n in _names())
        if (bases.contains(n.split(' (').first)) psxGame(n, launchboxId: launchboxId),
    ];

/// The fixture's files whose name starts with [prefix], in file order.
List<Game> psxGamesStartingWith(String prefix, {int? launchboxId}) => [
      for (final n in _names())
        if (n.startsWith(prefix)) psxGame(n, launchboxId: launchboxId),
    ];

/// Every file of the fixture.
List<Game> psxAll() => [for (final n in _names()) psxGame(n)];
