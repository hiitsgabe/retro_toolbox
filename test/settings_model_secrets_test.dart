import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/settings_model.dart';

void main() {
  test('o JSON salvo não leva as três credenciais do Internet Archive', () {
    const settings = AppSettings(iaAccessKey: 'AK', iaSecretKey: 'SK', iaCookies: 'logged-in-sig=xyz');

    final json = settings.toJson();

    expect(json.containsKey('iaAccessKey'), isFalse);
    expect(json.containsKey('iaSecretKey'), isFalse);
    expect(json.containsKey('iaCookies'), isFalse);
  });

  test('o JSON salvo não leva o token de console', () {
    const console = BaseSettings(downloadDir: '/roms/snes', authToken: 'tok-snes');

    final json = console.toJson();

    expect(json.containsKey('authToken'), isFalse);
    expect(json['downloadDir'], '/roms/snes');
  });

  test('ler o formato legado continua funcionando', () {
    // Assimetria deliberada: escreve sem, lê com. O arquivo de quem ainda não
    // migrou tem os campos lá, e quem os tira é a migração da Task 5, que roda
    // sobre o mapa cru. Tirar a leitura junto não fecharia buraco nenhum e
    // faria qualquer caminho que pule a migração perder o token em silêncio.
    final settings = AppSettings.fromJson({
      'iaAccessKey': 'AK',
      'consoleSettings': {
        'snes': {'authToken': 'tok-snes'},
      },
    });

    expect(settings.iaAccessKey, 'AK');
    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
  });

  test('o que não é segredo continua sendo salvo', () {
    const settings = AppSettings(nszDecompressEnabled: false, catalogSourceUrl: 'https://exemplo/consoles.json');

    final json = settings.toJson();

    expect(json['nszDecompressEnabled'], isFalse);
    expect(json['catalogSourceUrl'], 'https://exemplo/consoles.json');
  });
}
