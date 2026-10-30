import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// How a downloaded file is unpacked (catalog key `decompress`).
enum Decompress {
  none,
  unzip,
  unrar;

  /// Null means none; an unknown id is ignored (none) with a warning.
  static Decompress fromId(String? id) {
    if (id == null) return none;
    for (final d in values) {
      if (d.name == id) return d;
    }
    debugPrint('Unknown decompress "$id" ignored');
    return none;
  }

  /// Whether this method applies to [path], by its extension.
  bool matches(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (this) {
      none => false,
      unzip => ext == '.zip',
      unrar => ext == '.rar',
    };
  }
}

/// A conversion run on a game's files after download (catalog key
/// `additional_handler`): which extensions it takes and what it makes.
enum GameHandler {
  chdCompress('chd_compress', {'.cue', '.gdi', '.iso'}, '.chd', 'Convert to CHD'),
  cia3ds('3ds_convert', {'.3ds', '.cci'}, '.cia', 'Convert to CIA'),
  nszDecompress('nsz_decompress', {'.nsz'}, '.nsp', 'Decompress NSZ');

  const GameHandler(this.id, this.inputs, this.output, this.label);

  final String id;
  final Set<String> inputs;
  final String output;
  final String label;

  /// Null for null; an unknown id is ignored (null) with a warning.
  static GameHandler? fromId(String? id) {
    if (id == null) return null;
    for (final h in values) {
      if (h.id == id) return h;
    }
    debugPrint('Unknown additional_handler "$id" ignored');
    return null;
  }

  bool accepts(String path) => inputs.contains(p.extension(path).toLowerCase());
}

/// The handler that runs for a console: the user's saved choice ([saved] is a
/// handler id or 'none'), else the catalog's, where the old global NSZ switch
/// ([nszEnabled]) still turns the catalog's NSZ default off.
GameHandler? resolveActiveHandler({String? saved, GameHandler? jsonDefault, required bool nszEnabled}) {
  if (saved == 'none') return null;
  if (saved != null) return GameHandler.fromId(saved);
  if (jsonDefault == GameHandler.nszDecompress && !nszEnabled) return null;
  return jsonDefault;
}
