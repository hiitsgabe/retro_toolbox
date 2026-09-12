import 'dart:convert';
import 'dart:typed_data';

import 'package:roms_downloader/services/zip_central_directory.dart';

/// Uma entrada de diretório central: 46 bytes fixos, o nome, e o extra e o
/// comentário se pedidos. Só os campos que o parser lê são preenchidos, que é
/// o que um zip real também faz com a maioria deles.
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

/// Monta um zip inteiro: um bloco de zeros no lugar das entradas locais, o
/// diretório central, o EOCD, e um comentário depois dele.
///
/// O comentário depois do EOCD não é invenção de teste: o TorrentZip, que é o
/// formato que o archive.org serve, grava `TORRENTZIPPED-xxxxxxxx` ali. Se o
/// parser assumisse que o EOCD são os últimos 22 bytes do arquivo, ele
/// quebraria em cima de todo o acervo do archive.org.
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

/// Servidor falso de Range. Guarda o que foi pedido, para o teste conferir que
/// foram duas requisições curtas e não o arquivo inteiro.
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
