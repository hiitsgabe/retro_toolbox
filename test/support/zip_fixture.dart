import 'dart:convert';
import 'dart:typed_data';

import 'package:roms_downloader/services/zip_central_directory.dart';

/// A central directory entry: 46 fixed bytes, the name, then extra and comment
/// if asked. Only the fields the parser reads are filled.
Uint8List cdEntry(String name, int crc, {int extraLen = 0, int commentLen = 0}) {
  final nameBytes = utf8.encode(name);
  final head = ByteData(46);
  head.setUint32(0, 0x02014b50, Endian.little);
  head.setUint32(16, crc, Endian.little);
  head.setUint16(28, nameBytes.length, Endian.little);
  head.setUint16(30, extraLen, Endian.little);
  head.setUint16(32, commentLen, Endian.little);
  final out = BytesBuilder();
  out.add(head.buffer.asUint8List());
  out.add(nameBytes);
  out.add(Uint8List(extraLen));
  out.add(Uint8List(commentLen));
  return out.toBytes();
}

/// Builds a whole zip: a block of zeros for the local entries, the central
/// directory, the EOCD, and a comment after it. The comment is real: TorrentZip
/// (what archive.org serves) writes `TORRENTZIPPED-xxxxxxxx` there, so a parser
/// that assumed the EOCD is the last 22 bytes would break on every item.
Uint8List buildZip(
  List<Uint8List> entries, {
  int localBytes = 64,
  String comment = '',
  bool zip64 = false,
  int? forcedCdOffset,
  int? forcedCdSize,
}) {
  final cd = BytesBuilder();
  for (final entry in entries) {
    cd.add(entry);
  }
  final cdBytes = cd.toBytes();
  final commentBytes = utf8.encode(comment);
  final eocd = ByteData(22);
  eocd.setUint32(0, 0x06054b50, Endian.little);
  eocd.setUint16(8, entries.length, Endian.little);
  eocd.setUint16(10, entries.length, Endian.little);
  eocd.setUint32(12, forcedCdSize ?? (zip64 ? 0xFFFFFFFF : cdBytes.length),
      Endian.little);
  eocd.setUint32(16, forcedCdOffset ?? (zip64 ? 0xFFFFFFFF : localBytes),
      Endian.little);
  eocd.setUint16(20, commentBytes.length, Endian.little);
  final out = BytesBuilder();
  out.add(Uint8List(localBytes));
  out.add(cdBytes);
  out.add(eocd.buffer.asUint8List());
  out.add(commentBytes);
  return out.toBytes();
}

/// A fake Range server. Records what was asked so a test can check there were
/// two short requests and not the whole file.
class FakeRangeServer {
  final Uint8List body;
  final int status;
  final bool sendContentRange;
  final List<String> asked = [];

  FakeRangeServer(this.body, {this.status = 206, this.sendContentRange = true});

  Future<RangeResponse> fetch(Uri uri, String range) async {
    asked.add(range);
    final total = body.length;
    int start;
    int end;
    final suffix = RegExp(r'^bytes=-(\d+)$').firstMatch(range);
    if (suffix != null) {
      final n = int.parse(suffix.group(1)!);
      start = total - n < 0 ? 0 : total - n;
      end = total - 1;
    } else {
      final m = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range)!;
      start = int.parse(m.group(1)!);
      end = int.parse(m.group(2)!);
      if (end >= total) end = total - 1;
    }
    return RangeResponse(
      statusCode: status,
      contentRange: sendContentRange ? 'bytes $start-$end/$total' : null,
      bytes: Uint8List.sublistView(body, start, end + 1),
    );
  }
}
