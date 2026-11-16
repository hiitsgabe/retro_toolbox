import 'dart:convert';
import 'dart:io';

import 'launchbox_models.dart';
import 'launchbox_platforms.dart';

/// What the last finished import holds. Written after every platform file,
/// so a manifest on disk always describes complete files.
class LaunchboxManifest {
  const LaunchboxManifest({required this.etag, required this.importedAt, required this.platforms});

  /// Of the Metadata.zip this came from; null when the server sent none.
  final String? etag;
  final DateTime importedAt;

  /// LaunchBox platform names imported.
  final Set<String> platforms;

  Map<String, dynamic> toJson() => {
    'format': 1,
    'etag': etag,
    'importedAt': importedAt.toUtc().toIso8601String(),
    'platforms': platforms.toList()..sort(),
  };

  /// Null for junk or another format, which then reads as "never imported".
  static LaunchboxManifest? fromJson(Object? json) {
    if (json is! Map || json['format'] != 1) return null;
    final etag = json['etag'];
    final importedAt = json['importedAt'] is String ? DateTime.tryParse(json['importedAt'] as String) : null;
    final platforms = json['platforms'];
    if ((etag != null && etag is! String) || importedAt == null || platforms is! List) return null;
    return LaunchboxManifest(
      etag: etag as String?,
      importedAt: importedAt,
      platforms: {for (final p in platforms) if (p is String) p},
    );
  }
}

/// The imported metadata on disk: one gzip JSON list of games per platform
/// plus `manifest.json`, all under [root].
class LaunchboxStore {
  LaunchboxStore(this.root);

  /// `<app support>/launchbox`.
  final Directory root;

  File get _manifestFile => File('${root.path}/manifest.json');

  File platformFile(String platform) => File('${root.path}/${launchboxPlatformSlug(platform)}.json.gz');

  Future<LaunchboxManifest?> readManifest() async {
    try {
      return LaunchboxManifest.fromJson(jsonDecode(await _manifestFile.readAsString()));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeManifest(LaunchboxManifest m) => _writeAtomic(_manifestFile, utf8.encode(jsonEncode(m.toJson())));

  Future<void> writePlatform(String platform, List<LaunchboxGame> games) =>
      writePlatformBytes(platform, encodePlatform(games));

  /// [gzipBytes] as [encodePlatform] makes them; the import encodes in its
  /// isolate so this side only writes.
  Future<void> writePlatformBytes(String platform, List<int> gzipBytes) => _writeAtomic(platformFile(platform), gzipBytes);

  /// Raw gzip bytes, null when the platform was never imported. Decoding is
  /// left to [decodePlatform] so it can run off the UI isolate.
  Future<List<int>?> readPlatformBytes(String platform) async {
    try {
      return await platformFile(platform).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  static List<int> encodePlatform(List<LaunchboxGame> games) =>
      gzip.encode(utf8.encode(jsonEncode([for (final g in games) g.toJson()])));

  static List<LaunchboxGame> decodePlatform(List<int> gzipBytes) => [
    for (final j in jsonDecode(utf8.decode(gzip.decode(gzipBytes))) as List) LaunchboxGame.fromJson(j as Map<String, dynamic>),
  ];

  Future<void> deleteAll() async {
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Through `<name>.tmp` and a rename, so a crash mid-write leaves the
  /// previous file whole. A stale `.tmp` from such a crash is overwritten.
  Future<void> _writeAtomic(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }
}
