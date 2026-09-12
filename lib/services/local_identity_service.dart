import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/file_crc32.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

typedef FileCrc = Future<String> Function(File file);

/// O eixo da seção 5.7 do spec: identifica um arquivo que já está no disco.
///
/// Nome primeiro, CRC só na dúvida. Calcular CRC é a operação cara desta
/// fatia, e o tier de nome resolve a esmagadora maioria dos casos de graça.
///
/// Dart puro de propósito. Não adicione import de `package:flutter`.
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

  /// O que já foi calculado nesta sessão. Chave `tamanho|mtime|caminho`, valor
  /// o CRC em maiúsculas. Exposto para quem quiser persistir; nesta fatia
  /// ninguém persiste.
  Map<String, String> get cache => Map.unmodifiable(_cache);

  Future<GameMatch?> identify(File file) async {
    final name = p.basename(file.path);
    final byName = matcher.match(name);
    if (byName != null &&
        (byName.tier == MatchTier.exactName ||
            byName.tier == MatchTier.canonicalName)) {
      return byName;
    }

    // Um contêiner tem CRC próprio, que não é o da ROM, então calcular seria
    // gastar segundos para comparar com o índice errado. Ver 5.8, limite 1.
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
      // Arquivo sem permissão, meio copiado, ou num pendrive que sumiu. Nada
      // disso justifica derrubar a varredura da biblioteca inteira.
      return null;
    }
  }
}
