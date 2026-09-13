import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_metadata_model.dart';
import 'package:roms_downloader/models/game_details_model.dart';

class Game {
  final String title;
  final String url;
  final int size;
  final String consoleId;

  /// The id of the addon that served this file. Non-nullable: caches written
  /// before this field existed degrade to the default once in `fromJson`.
  final String sourceId;
  final GameMetadata? metadata;
  final GameDetails? details;

  const Game({
    required this.title,
    required this.url,
    required this.size,
    required this.consoleId,
    this.sourceId = kBuiltinAddonId,
    this.metadata,
    this.details,
  });

  Game copyWith({
    String? title,
    String? url,
    int? size,
    String? consoleId,
    String? sourceId,
    GameMetadata? metadata,
    GameDetails? details,
  }) {
    return Game(
      title: title ?? this.title,
      url: url ?? this.url,
      size: size ?? this.size,
      consoleId: consoleId ?? this.consoleId,
      sourceId: sourceId ?? this.sourceId,
      metadata: metadata ?? this.metadata,
      details: details ?? this.details,
    );
  }

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      title: json['title'],
      url: json['url'],
      size: json['size'],
      consoleId: json['consoleId'],
      sourceId: json['sourceId'] as String? ?? kBuiltinAddonId,
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
      'sourceId': sourceId,
      'metadata': metadata?.toJson(),
      'details': details?.toJson(),
    };
  }

  String get filename {
    final segments = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
    final last = segments.isEmpty ? '' : segments.last;
    return sanitizeForFat(last.contains('.') ? last : title);
  }

  // FAT/exFAT-illegal filename chars: one of these silently fails the write.
  static final _exfatIllegal = RegExp(r'[<>:"/\\|?*\x00-\x1f]');

  static String sanitizeForFat(String name) {
    final cleaned = name
        .replaceAll(_exfatIllegal, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'output' : cleaned;
  }

  String get gameId => '$consoleId/$filename';

  String get displayTitle => metadata?.displayTitle ?? title;

  String get region => metadata?.regions.firstOrNull ?? '';

  String get language => metadata?.languages.firstOrNull ?? '';

  String? get boxart => details?.boxart;
}
