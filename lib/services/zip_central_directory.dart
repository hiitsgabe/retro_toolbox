import 'dart:io';
import 'dart:typed_data';

/// A resposta de uma requisição com header `Range`, reduzida ao que o parser
/// precisa. Existe para o teste poder responder sem rede.
class RangeResponse {
  final int statusCode;
  final String? contentRange;
  final Uint8List bytes;

  const RangeResponse({
    required this.statusCode,
    required this.bytes,
    this.contentRange,
  });
}

/// Busca um intervalo de bytes. [range] já vem pronto, no formato do header:
/// `bytes=-256` ou `bytes=100-199`.
typedef RangeFetch = Future<RangeResponse> Function(Uri uri, String range);

/// Lê o diretório central de um ZIP remoto em duas requisições curtas.
///
/// Dart puro de propósito: `tool/probe_zip_cd.dart` roda isto fora do Flutter.
/// Não adicione import de `package:flutter`.
class ZipCentralDirectory {
  /// Quantos bytes do fim buscar para achar o EOCD. 256 cobre os 22 bytes do
  /// EOCD mais um comentário curto, incluindo o `TORRENTZIPPED-xxxxxxxx` de
  /// 22 caracteres que o archive.org grava. Zip com comentário maior sai fora,
  /// e isso é aceitável: virar duas requisições em três não paga o ganho.
  static const tailBytes = 256;

  /// Teto do que aceitamos bufferizar. Um diretório central acima disso é um
  /// zip com dezenas de milhares de entradas, que não é o caso de uso, e
  /// aceitar significa deixar um servidor hostil encher a memória do app.
  static const maxDirectoryBytes = 8 * 1024 * 1024;

  /// Os bytes crus do diretório central, ou null quando não deu.
  ///
  /// Null nunca é erro fatal: quem chama simplesmente fica com o palpite de
  /// nome. Este método não levanta.
  static Future<Uint8List?> readRaw(Uri uri, RangeFetch fetch) async {
    final RangeResponse tail;
    try {
      tail = await fetch(uri, 'bytes=-$tailBytes');
    } catch (_) {
      return null;
    }
    final total = _totalFrom(tail);
    if (total == null) return null;

    final eocd = _findEocd(tail.bytes);
    if (eocd == null) return null;

    final view = ByteData.sublistView(tail.bytes);
    final size = view.getUint32(eocd + 12, Endian.little);
    final offset = view.getUint32(eocd + 16, Endian.little);

    // 0xFFFFFFFF nos dois campos é o marcador de zip64: o valor real está num
    // registro separado, antes do EOCD. Nenhuma fonte de ROM serve zip64, e
    // implementar isso por completude seria código morto.
    if (size == 0xFFFFFFFF || offset == 0xFFFFFFFF) return null;
    if (size == 0 || size > maxDirectoryBytes) return null;
    if (offset + size > total) return null;

    final RangeResponse body;
    try {
      body = await fetch(uri, 'bytes=$offset-${offset + size - 1}');
    } catch (_) {
      return null;
    }
    if (_totalFrom(body) == null) return null;
    if (body.bytes.length != size) return null;
    return body.bytes;
  }

  /// O tamanho total do arquivo, extraído do `Content-Range`, ou null se a
  /// resposta não for uma resposta parcial de verdade.
  ///
  /// As duas condições juntas são a guarda da seção 5.8, limite 2. Um `200`
  /// significa que o servidor ignorou o `Range` e está mandando o arquivo
  /// inteiro, ou uma página de erro com cara de sucesso.
  static int? _totalFrom(RangeResponse response) {
    if (response.statusCode != HttpStatus.partialContent) return null;
    final header = response.contentRange;
    if (header == null) return null;
    final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(header.trim());
    if (m == null) return null;
    return int.parse(m.group(3)!);
  }

  /// Varre de trás para frente atrás de `PK\x05\x06`. De trás para frente
  /// porque o EOCD é o último registro, mas não necessariamente os últimos
  /// bytes: o comentário vem depois dele.
  static int? _findEocd(Uint8List bytes) {
    if (bytes.length < 22) return null;
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        return i;
      }
    }
    return null;
  }

  /// O fetch de produção.
  ///
  /// A ordem das linhas importa: **confira o status antes de consumir o
  /// corpo**. Ler primeiro e checar depois significa baixar o arquivo inteiro,
  /// que é exatamente o que a leitura por Range existe para evitar.
  ///
  /// O `HttpClient` segue redirect sozinho e preserva o header `Range` ao
  /// fazê-lo, o que foi conferido contra o archive.org, que responde 302 antes
  /// do 206.
  static Future<RangeResponse> httpRangeFetch(Uri uri, String range) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        return RangeResponse(
          statusCode: response.statusCode,
          bytes: Uint8List(0),
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxDirectoryBytes) {
          throw HttpException(
              'resposta parcial acima de $maxDirectoryBytes bytes',
              uri: uri);
        }
      }
      return RangeResponse(
        statusCode: response.statusCode,
        contentRange: response.headers.value(HttpHeaders.contentRangeHeader),
        bytes: builder.toBytes(),
      );
    } finally {
      client.close(force: true);
    }
  }
}
