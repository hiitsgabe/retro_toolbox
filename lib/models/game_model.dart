import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_group_model.dart';
import 'package:retro_toolbox/models/game_update_model.dart';

class Game {
  final String title;
  final String url;
  final int size;
  final String consoleId;
  final GameMetadata? metadata;
  final GameDetails? details;

  /// A grouped multi-disc game's discs, this one included, by disc number;
  /// empty otherwise. Set by the list's grouping, never saved.
  final List<Game> discs;

  /// Updates the catalog lists for this game, newest last as the feed has
  /// them; empty when it lists none.
  final List<GameUpdate> updates;

  /// An update of a catalog game (see GameUpdate.toGame): it downloads to the
  /// console's updates folder, with the console's choices for updates.
  final bool isUpdate;

  /// The game this entry stands for, with its versions and extras. Set by
  /// the list's grouping, never saved.
  final GameGroup? group;

  const Game({
    required this.title,
    required this.url,
    required this.size,
    required this.consoleId,
    this.metadata,
    this.details,
    this.discs = const [],
    this.updates = const [],
    this.isUpdate = false,
    this.group,
  });

  Game copyWith({
    String? title,
    String? url,
    int? size,
    String? consoleId,
    GameMetadata? metadata,
    GameDetails? details,
    List<Game>? discs,
    List<GameUpdate>? updates,
    bool? isUpdate,
    GameGroup? group,
  }) {
    return Game(
      title: title ?? this.title,
      url: url ?? this.url,
      size: size ?? this.size,
      consoleId: consoleId ?? this.consoleId,
      metadata: metadata ?? this.metadata,
      details: details ?? this.details,
      discs: discs ?? this.discs,
      updates: updates ?? this.updates,
      isUpdate: isUpdate ?? this.isUpdate,
      group: group ?? this.group,
    );
  }

  /// Minimal Game rebuilt from a downloader task id (`consoleId/filename`, the
  /// same shape as [gameId]) so a download restored after a crash can show in
  /// the task manager. Null when the id isn't in that shape.
  static Game? fromTaskId(String taskId, String filename) {
    final slash = taskId.indexOf('/');
    if (slash <= 0) return null;
    return Game(
      title: filename,
      url: 'https://restored/${Uri.encodeComponent(filename)}',
      size: 0,
      consoleId: taskId.substring(0, slash),
    );
  }

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      title: json['title'],
      url: json['url'],
      size: json['size'],
      consoleId: json['consoleId'],
      metadata: json['metadata'] != null ? GameMetadata.fromJson(json['metadata']) : null,
      details: json['details'] != null ? GameDetails.fromJson(json['details']) : null,
      updates: [for (final u in (json['updates'] as List? ?? const [])) GameUpdate.fromJson(Map<String, dynamic>.from(u as Map))],
      isUpdate: json['isUpdate'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'size': size,
      'consoleId': consoleId,
      'metadata': metadata?.toJson(),
      'details': details?.toJson(),
      if (updates.isNotEmpty) 'updates': [for (final u in updates) u.toJson()],
      if (isUpdate) 'isUpdate': true,
    };
  }

  String get filename {
    final segments = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
    final last = segments.isEmpty ? '' : segments.last;
    // API-style URLs (e.g. .../download/<id>/base) carry no real filename —
    // fall back to the title so ids stay unique and files get proper names.
    return sanitizeForFat(last.contains('.') ? last : title);
  }

  // FAT/exFAT-illegal filename chars. Handheld ROM SD cards are almost always
  // exFAT; creating a file whose name contains one of these fails with EPERM on
  // the FUSE mount — a title like "...Prime 4: Beyond" (colon) silently fails to
  // download/extract while a legal-named title in the same folder works. Every
  // on-disk path derives from this getter, so sanitizing here keeps download,
  // extraction and library-snapshot all agreeing on one safe name.
  static final _exfatIllegal = RegExp(r'[<>:"/\\|?*\x00-\x1f]');

  static String sanitizeForFat(String name) {
    final cleaned = name
        .replaceAll(_exfatIllegal, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'[. ]+$'), ''); // trailing dot/space also illegal
    return cleaned.isEmpty ? 'output' : cleaned;
  }

  String get gameId => '$consoleId/$filename';

  /// A box set shows as the box; anything else by its parsed title.
  String get displayTitle => group?.isBoxSet == true ? group!.title : metadata?.displayTitle ?? title;

  String get region => metadata?.regions.firstOrNull ?? '';

  String get language => metadata?.languages.firstOrNull ?? '';

  /// LaunchBox's cover when Settings chose it and LaunchBox has one, else the
  /// catalog's box art.
  String? get boxart => details?.launchboxCover ?? details?.boxart;
}
