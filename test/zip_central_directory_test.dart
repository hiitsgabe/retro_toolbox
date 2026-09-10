import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

import 'support/zip_fixture.dart';

void main() {
  final uri = Uri.parse('https://exemplo/arquivo.zip');
  final entry = cdEntry('Chrono Trigger (USA).sfc', 0x2D206BF7);

  test('devolve exatamente os bytes do diretório central', () async {
    final server = FakeRangeServer(buildZip([entry]));
    final raw = await ZipCentralDirectory.readRaw(uri, server.fetch);
    expect(raw, isNotNull);
    expect(raw, orderedEquals(entry));
  });

  test('faz duas requisições: o sufixo e o intervalo exato', () async {
    final server = FakeRangeServer(buildZip([entry], localBytes: 500));
    await ZipCentralDirectory.readRaw(uri, server.fetch);
    expect(server.asked, [
      'bytes=-256',
      'bytes=500-${500 + entry.length - 1}',
    ]);
  });

  test('acha o EOCD mesmo com o comentário do TorrentZip depois dele', () async {
    final server = FakeRangeServer(
        buildZip([entry], comment: 'TORRENTZIPPED-58A7B7DC'));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch),
        orderedEquals(entry));
  });

  test('devolve null quando o servidor ignora o Range e responde 200', () async {
    // O caso do Myrient, seção 5.8 limite 2. Sem esta guarda o parser tentaria
    // achar um EOCD dentro de uma página HTML.
    final server = FakeRangeServer(buildZip([entry]), status: 200);
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('devolve null quando não vem Content-Range', () async {
    final server =
        FakeRangeServer(buildZip([entry]), sendContentRange: false);
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
  });

  test('devolve null em zip64', () async {
    final server = FakeRangeServer(buildZip([entry], zip64: true));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('devolve null quando o diretório central cai fora do arquivo', () async {
    final server = FakeRangeServer(buildZip([entry], forcedCdOffset: 900000));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('devolve null quando o EOCD não cabe nos 256 bytes finais', () async {
    final server =
        FakeRangeServer(buildZip([entry], comment: 'x' * 300));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
  });

  test('devolve null quando a rede levanta exceção', () async {
    Future<RangeResponse> explode(Uri uri, String range) async =>
        throw const SocketException('sem rede');
    expect(await ZipCentralDirectory.readRaw(uri, explode), isNull);
  });

  group('entradas', () {
    test('lê nome e CRC de uma entrada', () {
      final entries = ZipCentralDirectory.parse(entry);
      expect(entries, hasLength(1));
      expect(entries!.single.name, 'Chrono Trigger (USA).sfc');
      expect(entries.single.crc, '2D206BF7');
    });

    test('lê várias entradas mesmo com extra e comentário entre elas', () {
      final blob = BytesBuilder()
        ..add(cdEntry('a.sfc', 0x00000001, extraLen: 9))
        ..add(cdEntry('b.sfc', 0x000000FF, commentLen: 5))
        ..add(cdEntry('c.sfc', 0xA31BEAD4));
      final entries = ZipCentralDirectory.parse(blob.toBytes());
      expect(entries?.map((e) => e.name), ['a.sfc', 'b.sfc', 'c.sfc']);
      expect(entries?.map((e) => e.crc),
          ['00000001', '000000FF', 'A31BEAD4']);
    });

    test('crcMatchesRom só aceita a ROM em si', () {
      bool rom(String name) =>
          ZipCentralDirectory.parse(cdEntry(name, 1))!.single.crcMatchesRom;
      expect(rom('Chrono Trigger (USA).sfc'), isTrue);
      expect(rom('Chrono Trigger (USA).iso'), isTrue);
      // Contêiner dentro de contêiner: o CRC é do comprimido, não da ROM.
      expect(rom('Chrono Trigger (USA).zip'), isFalse);
      expect(rom('Chrono Trigger (USA).7z'), isFalse);
      // Não é ROM nenhuma.
      expect(rom('leiame.txt'), isFalse);
    });

    test('para no lixo e devolve o que já tinha lido', () {
      final blob = BytesBuilder()
        ..add(cdEntry('a.sfc', 0x00000001))
        ..add(Uint8List.fromList(List.filled(60, 0x41)));
      expect(ZipCentralDirectory.parse(blob.toBytes())?.map((e) => e.name),
          ['a.sfc']);
    });

    test('read junta as duas metades e entrega as entradas', () async {
      final server = FakeRangeServer(buildZip([
        cdEntry('Super Mario World (Europe).sfc', 0xA31BEAD4),
        cdEntry('leiame.txt', 0x00000009),
      ]));
      final entries = await ZipCentralDirectory.read(uri, server.fetch);
      expect(entries?.map((e) => e.name),
          ['Super Mario World (Europe).sfc', 'leiame.txt']);
      expect(entries?.where((e) => e.crcMatchesRom).single.crc, 'A31BEAD4');
    });
  });
}
