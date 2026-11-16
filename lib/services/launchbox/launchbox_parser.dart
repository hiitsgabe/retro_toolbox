import 'dart:convert';

import 'package:xml/xml_events.dart';

import 'launchbox_models.dart';
import 'zip_entry_stream.dart';

/// Games of [platforms] in the zip's Metadata.xml, by platform. Every
/// requested platform has a key, with an empty list when it has no games.
/// [onProgress] gets 0..1 as the compressed bytes are consumed; it may throw
/// to stop the parse (the exception propagates).
Future<Map<String, List<LaunchboxGame>>> parseLaunchboxZip(
  String zipPath,
  Set<String> platforms, {
  void Function(double fraction)? onProgress,
}) async {
  final entry = await findZipEntry(zipPath, 'Metadata.xml');
  var lastPercent = -1;
  final bytes = zipEntryStream(
    zipPath,
    entry,
    onCompressedRead: onProgress == null
        ? null
        : (read) {
            // Called per 64 KB chunk; whole percents are plenty for a progress bar.
            final percent = read * 100 ~/ entry.compressedSize;
            if (percent == lastPercent) return;
            lastPercent = percent;
            onProgress(percent / 100);
          },
  );
  return parseLaunchboxXml(bytes, platforms);
}

/// Same, over an already uncompressed XML byte stream (tests use this).
Future<Map<String, List<LaunchboxGame>>> parseLaunchboxXml(Stream<List<int>> xml, Set<String> platforms) async {
  final games = <String, List<LaunchboxGame>>{for (final p in platforms) p: []};
  final keptIds = <int>{};
  final seenIds = <int>{};
  // Alternate names and images by game id. The real file lists every game
  // first, but nothing promises it, so rows for games not seen yet are held
  // here too; rows of games already seen and dropped are not.
  final altNames = <int, List<String>>{};
  final images = <int, List<LaunchboxImage>>{};

  bool wanted(int id) => keptIds.contains(id) || !seenIds.contains(id);

  void record(String kind, Map<String, String> f) {
    switch (kind) {
      case 'Game':
        final game = launchboxGameFromFields(f);
        if (game == null) return;
        seenIds.add(game.id);
        final list = games[f['Platform']?.trim()];
        if (list == null) {
          altNames.remove(game.id);
          images.remove(game.id);
          return;
        }
        keptIds.add(game.id);
        list.add(game);
      case 'GameAlternateName':
        final id = int.tryParse(f['DatabaseID']?.trim() ?? '');
        final name = f['AlternateName']?.trim() ?? '';
        if (id == null || name.isEmpty || !wanted(id)) return;
        altNames.putIfAbsent(id, () => []).add(name);
      case 'GameImage':
        final id = int.tryParse(f['DatabaseID']?.trim() ?? '');
        final type = LaunchboxImageType.fromXml(f['Type']?.trim() ?? '');
        final file = f['FileName']?.trim() ?? '';
        if (id == null || type == null || file.isEmpty || !wanted(id)) return;
        final region = f['Region']?.trim();
        images.putIfAbsent(id, () => []).add(LaunchboxImage(type, file, region == null || region.isEmpty ? null : region));
    }
  }

  // Depth 1 elements are the records, depth 2 their fields, and the text
  // inside a field is at depth 3. Records of other kinds are skipped whole.
  var depth = 0;
  var rootClosed = false;
  String? kind;
  String? field;
  var fields = <String, String>{};
  final text = StringBuffer();
  // bind, not transform: File.openRead is a Stream<Uint8List>, which
  // transform() rejects for a List<int> decoder.
  final events = utf8.decoder.bind(xml).toXmlEvents().normalizeEvents().flatten();
  await for (final e in events) {
    if (e is XmlStartElementEvent) {
      if (depth == 0 && e.name != 'LaunchBox') throw FormatException('Not a LaunchBox Metadata.xml', e.name);
      if (depth == 1) {
        kind = const {'Game', 'GameAlternateName', 'GameImage'}.contains(e.name) ? e.name : null;
        fields = {};
        if (e.isSelfClosing && kind != null) record(kind, fields);
      } else if (depth == 2 && kind != null) {
        field = e.name;
        text.clear();
        if (e.isSelfClosing) fields[e.name] = '';
      }
      if (!e.isSelfClosing) depth++;
    } else if (e is XmlTextEvent) {
      if (depth == 3 && kind != null) text.write(e.value);
    } else if (e is XmlCDATAEvent) {
      if (depth == 3 && kind != null) text.write(e.value);
    } else if (e is XmlEndElementEvent) {
      depth--;
      if (depth == 2 && kind != null && field != null) {
        fields[field] = text.toString();
        field = null;
      } else if (depth == 1 && kind != null) {
        record(kind, fields);
        kind = null;
      } else if (depth == 0) {
        rootClosed = true;
      }
    }
  }
  // The event parser does not complain about input that just stops, and a
  // partial result would replace good per-platform files.
  if (!rootClosed) throw const FormatException('Metadata.xml ended before </LaunchBox>');

  return {
    for (final MapEntry(key: platform, value: list) in games.entries)
      platform: [
        for (final g in list) g.withExtras(alternateNames: _alternateNames(g, altNames[g.id]), images: _sortedImages(images[g.id])),
      ],
  };
}

List<String> _alternateNames(LaunchboxGame game, List<String>? names) =>
    names == null ? const [] : {...names}.where((n) => n != game.name).toList();

/// Type order, then file name, so the output does not depend on row order.
List<LaunchboxImage> _sortedImages(List<LaunchboxImage>? images) {
  if (images == null) return const [];
  return images
    ..sort((a, b) {
      final byType = a.type.index.compareTo(b.type.index);
      return byType != 0 ? byType : a.file.compareTo(b.file);
    });
}
