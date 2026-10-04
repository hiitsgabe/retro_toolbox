import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';

class Game {
  final String title;
  final String url;
  final int size;
  final String consoleId;
  final GameMetadata? metadata;
  final GameDetails? details;

  const Game({
    required this.title,
    required this.url,
    required this.size,
    required this.consoleId,
    this.metadata,
    this.details,
  });

  Game copyWith({
    String? title,
    String? url,
    int? size,
    String? consoleId,
    GameMetadata? metadata,
    GameDetails? details,
  }) {
    return Game(
      title: title ?? this.title,
      url: url ?? this.url,
      size: size ?? this.size,
      consoleId: consoleId ?? this.consoleId,
      metadata: metadata ?? this.metadata,
      details: details ?? this.details,
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

  String get displayTitle => metadata?.displayTitle ?? title;

  String get region => metadata?.regions.firstOrNull ?? '';

  String get language => metadata?.languages.firstOrNull ?? '';

  String? get boxart => details?.boxart;
}
