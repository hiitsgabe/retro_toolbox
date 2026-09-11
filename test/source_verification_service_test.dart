import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_verification_service.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

/// CRCs do pacote de teste, na forma numérica que o diretório central grava.
const chronoUsa = 0x2D206BF7;
const chronoJapan = 0xABCD1234;
const smwEurope = 0xA31BEAD4;
const forasteiro = 0xDEADBEEF;

const chrono = 'snes/chrono-trigger';

void main() {
  late PackMatcher matcher;
  final uri = Uri.parse('https://exemplo/arquivo.zip');

  setUp(() => matcher = PackMatcher(buildPack()));

  test('não vai à rede quando o arquivo não é zip', () async {
    var chamadas = 0;
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: (u, r) async {
        chamadas++;
        throw StateError('não deveria ter ido à rede');
      },
    );

    final out = await service.verify(uri, 'Chrono Trigger (USA).7z', chrono);

    // Não existe leitor de 7z ou rar por Range. Impossível não é "fonte
    // ruim", é "não dá para saber".
    expect(out, SourceVerification.impossible);
    expect(chamadas, 0);
  });

  test('o CRC de dentro é um dump deste jogo', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)])).fetch,
    );

    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.crcOk,
    );
  });

  test('qualquer dump do jogo serve, não precisa ser o do nome', () async {
    // O arquivo se chama USA e contém o dump japonês. Continua sendo Chrono
    // Trigger, e a pergunta desta classe é sobre o jogo, não sobre a versão.
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', chronoJapan)])).fetch,
    );

    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.crcOk,
    );
  });

  test('o CRC de dentro é de outro jogo', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', smwEurope)])).fetch,
    );

    // O nome mente e o CRC desmente. Esta é a fonte que a seção 8 manda
    // descartar do destaque.
    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.crcDiscarded,
    );
  });

  test('o CRC de dentro não é de jogo nenhum do pacote', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', forasteiro)])).fetch,
    );

    // Um hack, um bad dump, uma tradução. Não é este jogo, então desce.
    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.crcDiscarded,
    );
  });

  test('zip sem ROM dentro não desmente nada', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([
        cdEntry('leiame.txt', forasteiro),
        cdEntry('bonus.zip', forasteiro),
      ])).fetch,
    );

    // Nenhuma das duas entradas tem CRC comparável com o pacote (seção 5.8,
    // limite 1), então não há evidência nem a favor nem contra.
    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.impossible,
    );
  });

  test('o servidor que não fala Range deixa a verificação impossível', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(
        buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]),
        status: 200,
      ).fetch,
    );

    expect(
      await service.verify(uri, 'Chrono Trigger (USA).zip', chrono),
      SourceVerification.impossible,
    );
  });

  test('são duas requisições curtas, e não o arquivo inteiro', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Chrono Trigger (USA).sfc', chronoUsa)]));
    final service = SourceVerificationService(matcher: matcher, fetch: server.fetch);

    await service.verify(uri, 'Chrono Trigger (USA).zip', chrono);

    // Os 326 bytes da seção 8: um sufixo para achar o EOCD e um intervalo
    // exato para o diretório central.
    expect(server.asked.length, 2);
    expect(server.asked.first, 'bytes=-256');
  });
}
