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
}
