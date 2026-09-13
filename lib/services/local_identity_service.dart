import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/file_crc32.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

typedef FileCrc = Future<String> Function(File file);

/// Identifies a file already on disk: name first, CRC only when in doubt.
///
/// Pure Dart on purpose. Do not add a `package:flutter` import.
class LocalIdentityService {
  final PackMatcher matcher;
  final FileCrc crcOfFile;
  final Map<String, String> _cache;

  LocalIdentityService({
    required this.matcher,
    FileCrc? crcOfFile,
    Map<String, String>? initialCache,
  })  : crcOfFile = crcOfFile ?? crc32OfFile,
        _cache = {...?initialCache};

  /// What was computed this session. Key `size|mtime|path`, value the uppercase
  /// CRC.
  Map<String, String> get cache => Map.unmodifiable(_cache);

  Future<GameMatch?> identify(File file) async {
    final name = p.basename(file.path);
    final byName = matcher.match(name);
    if (byName != null &&
        (byName.tier == MatchTier.exactName ||
            byName.tier == MatchTier.canonicalName)) {
      return byName;
    }

    // A container has its own CRC, not the ROM's; computing it would compare
    // against the wrong index.
    if (hasArchiveExtension(name)) return byName;

    final crc = await _crcOf(file);
    if (crc == null) return byName;
    return matcher.matchCrc(crc, sourceName: name) ?? byName;
  }

  Future<String?> _crcOf(File file) async {
    final FileStat stat;
    try {
      stat = await file.stat();
    } catch (_) {
      return null;
    }
    if (stat.type == FileSystemEntityType.notFound) return null;
    final key =
        '${stat.size}|${stat.modified.millisecondsSinceEpoch}|${file.path}';
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final crc = await crcOfFile(file);
      _cache[key] = crc;
      return crc;
    } catch (_) {
      return null;
    }
  }
}
