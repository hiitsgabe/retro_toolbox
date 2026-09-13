import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/utils/console_auth.dart';
import 'package:roms_downloader/utils/network.dart';

void main() {
  group('buildConsoleAuthHeaders', () {
    test('token from the catalog file is ignored', () {
      // The catalog is a file the user shares; nothing encrypts it and nothing
      // warns that a secret is inside. After this fix, the field can be present
      // but it does not authenticate anyone.
      final headers = buildConsoleAuthHeaders({'token': 'tok-from-file'});

      expect(headers, isEmpty);
    });

    test('caller token builds a Bearer header', () {
      final headers = buildConsoleAuthHeaders({}, tokenOverride: 'tok-from-vault');

      expect(headers, {'Authorization': 'Bearer tok-from-vault'});
    });

    test('cookies mode builds a Cookie header with the catalog name', () {
      final headers = buildConsoleAuthHeaders(
        {'cookies': true, 'cookie_name': 'ultranx_session'},
        tokenOverride: 'tok-from-vault',
      );

      expect(headers, {'Cookie': 'ultranx_session=tok-from-vault'});
    });

    test('missing cookie_name falls back to auth_token', () {
      final headers = buildConsoleAuthHeaders({'cookies': true}, tokenOverride: 'tok-from-vault');

      expect(headers, {'Cookie': 'auth_token=tok-from-vault'});
    });

    test('ia_s3 type builds no header even with a caller token', () {
      // Internet Archive signs requests differently; a Bearer here would break
      // the download instead of authenticating.
      final headers = buildConsoleAuthHeaders({'type': 'ia_s3'}, tokenOverride: 'tok-from-vault');

      expect(headers, isEmpty);
    });

    test('null auth builds no header', () {
      expect(buildConsoleAuthHeaders(null, tokenOverride: 'tok-from-vault'), isEmpty);
    });
  });

  group('consoleHasToken', () {
    test('catalog token does not count as connected', () {
      // Without this case the Tinfoil screen and the wizard show "connected"
      // reading a field that the fix just removed from the auth path.
      const settings = AppSettings();

      expect(consoleHasToken(settings, 'ultranx'), isFalse);
    });

    test('settings token counts as connected', () {
      const settings = AppSettings(consoleSettings: {'ultranx': BaseSettings(authToken: 'tok-from-vault')});

      expect(consoleHasToken(settings, 'ultranx'), isTrue);
    });

    test('empty token does not count as connected', () {
      const settings = AppSettings(consoleSettings: {'ultranx': BaseSettings(authToken: '')});

      expect(consoleHasToken(settings, 'ultranx'), isFalse);
    });
  });
}
