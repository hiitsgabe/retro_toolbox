import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/secret_ref.dart';

void main() {
  test('token key carries addon then console', () {
    expect(SecretRef.addonToken('ultranx', 'nintendo_64'), 'addon:ultranx/nintendo_64');
  });

  test('two addons on the same console get distinct keys', () {
    expect(
      SecretRef.addonToken('ultranx', 'nintendo_64'),
      isNot(SecretRef.addonToken('meu_rts', 'nintendo_64')),
    );
  });

  test('Internet Archive keys', () {
    expect(SecretRef.iaAccessKey, 'ia/accessKey');
    expect(SecretRef.iaSecretKey, 'ia/secretKey');
    expect(SecretRef.iaCookies, 'ia/cookies');
  });

  test('debrid key is per provider', () {
    expect(SecretRef.debrid('realdebrid'), 'debrid/realdebrid');
  });

  test('addon prefix matches only that addon keys', () {
    final prefix = SecretRef.addonPrefix('ultranx');

    expect(SecretRef.addonToken('ultranx', 'nintendo_64').startsWith(prefix), isTrue);
    expect(SecretRef.addonToken('ultranx', 'snes').startsWith(prefix), isTrue);
    expect(SecretRef.addonToken('ultranx_2', 'snes').startsWith(prefix), isFalse);
    expect(SecretRef.iaAccessKey.startsWith(prefix), isFalse);
  });

  test('a slash or colon in an id cannot forge another key', () {
    expect(
      SecretRef.addonToken('a/b', 'c'),
      isNot(SecretRef.addonToken('a', 'b/c')),
    );
  });

  test('sanitizing keeps ids that differ only in punctuation apart', () {
    expect(SecretRef.addonToken('meu-rts', 'snes'), isNot(SecretRef.addonToken('meu_rts', 'snes')));
  });
}
