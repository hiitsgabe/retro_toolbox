import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

Console _console(String id, List<String> urls, {Map<String, dynamic>? auth}) =>
    Console(id: id, name: id.toUpperCase(), urls: urls, auth: auth);

AddonCatalog _catalog(String addonId, Map<String, Console> consoles) => (addonId: addonId, consoles: consoles);

void main() {
  group('authNeedsToken', () {
    test('console with no auth block needs no token', () {
      expect(authNeedsToken(null), isFalse);
    });

    test('the harvest mark alone is enough', () {
      // `requires_token` is what the harvest writes in place of the token it
      // strips from the shareable file.
      expect(authNeedsToken(const {'requires_token': true}), isTrue);
    });

    test('the raw catalog field still counts', () {
      // The built-in never went through the harvest, nor did a hand-opened file.
      expect(authNeedsToken(const {'token': 'tok'}), isTrue);
    });

    test('the login message alone counts', () {
      expect(authNeedsToken(const {'auth_message': 'Ask for an invite on the forum.'}), isTrue);
    });

    test('ia_s3 needs no token, even with the mark', () {
      // Internet Archive signs differently and has its own screen in Accounts.
      expect(authNeedsToken(const {'type': 'ia_s3', 'requires_token': true}), isFalse);
    });

    test('auth that says nothing about a token needs none', () {
      expect(authNeedsToken(const {'cookies': true, 'cookie_name': 'sess'}), isFalse);
    });

    test('hasTokenAuth is the function, not a second rule', () {
      // Guards against the duplication returning: if someone edits one of the
      // two places, this expect stops holding.
      const auth = {'requires_token': true};
      expect(_console('snes', const ['https://a/'], auth: auth).hasTokenAuth, authNeedsToken(auth));
      expect(_console('snes', const ['https://a/']).hasTokenAuth, authNeedsToken(null));
    });
  });

  group('authForAddon', () {
    final merged = mergeCatalogs([
      _catalog('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
      _catalog('ultranx', {
        'snes': _console('snes', const ['https://ultranx/snes/'], auth: const {'token': 'tok', 'cookies': true}),
      }),
    ]);

    test('returns the auth of the requested addon\'s source', () {
      expect(authForAddon(merged.sources['snes']!, 'ultranx'), {'token': 'tok', 'cookies': true});
    });

    test('addon that does not serve this console returns null', () {
      expect(authForAddon(merged.sources['snes']!, 'someones-archive'), isNull);
    });

    test('addon that serves without declaring auth also returns null', () {
      // Both absences become the same `null` on purpose: the reader treats them
      // alike, sending no header.
      expect(authForAddon(merged.sources['snes']!, 'myrient'), isNull);
    });

    test('between two sources of the same addon, the first wins', () {
      const list = [
        ConsoleSource(addonId: 'a', url: 'https://one/', auth: {'token': 'first'}),
        ConsoleSource(addonId: 'a', url: 'https://two/', auth: {'token': 'second'}),
      ];

      expect(authForAddon(list, 'a'), {'token': 'first'});
    });
  });

  group('coverage', () {
    test('lists each addon\'s consoles', () {
      final merged = mergeCatalogs([
        _catalog('myrient', {
          'snes': _console('snes', const ['https://myrient/snes/']),
          'md': _console('md', const ['https://myrient/md/']),
        }),
        _catalog('ultranx', {'switch': _console('switch', const ['https://ultranx/'])}),
      ]);

      expect(merged.coverage()['myrient']!.consoles, ['snes', 'md']);
      expect(merged.coverage()['ultranx']!.consoles, ['switch']);
    });

    test('a console served by two addons counts for both', () {
      final merged = mergeCatalogs([
        _catalog('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
        _catalog('acme', {'snes': _console('snes', const ['https://acme/snes/'])}),
      ]);

      expect(merged.coverage()['myrient']!.consoles, ['snes']);
      expect(merged.coverage()['acme']!.consoles, ['snes']);
    });

    test('two urls of the same addon on the same console count one console', () {
      // The count is "25 consoles", not "25 urls". One more mirror does not make
      // the source bigger.
      final merged = mergeCatalogs([
        _catalog('myrient', {
          'snes': _console('snes', const ['https://myrient/snes/', 'https://mirror/snes/']),
        }),
      ]);

      expect(merged.coverage()['myrient']!.consoles, ['snes']);
    });

    test('authConsoles carries only the consoles that need an account', () {
      final merged = mergeCatalogs([
        _catalog('ultranx', {
          'switch': _console('switch', const ['https://ultranx/switch/'], auth: const {'requires_token': true}),
          'wiiu': _console('wiiu', const ['https://ultranx/wiiu/']),
        }),
      ]);

      final coverage = merged.coverage()['ultranx']!;

      expect(coverage.consoles, ['switch', 'wiiu']);
      expect(coverage.authConsoles, ['switch']);
    });

    test('addon with no account on any console has empty authConsoles', () {
      // This empty is what hides the account chip, and it must be an empty list,
      // not `null`: the screen asks `isNotEmpty`.
      final merged = mergeCatalogs([
        _catalog('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
      ]);

      expect(merged.coverage()['myrient']!.authConsoles, isEmpty);
    });

    test('addon serving no console does not appear in the map', () {
      // A freshly installed addon whose catalog is not read yet, or one whose
      // url died. The row treats absent as zero, so the screen uses a fallback
      // record instead of `!`.
      final merged = mergeCatalogs([
        _catalog('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
        _catalog('empty', const {}),
      ]);

      expect(merged.coverage().containsKey('empty'), isFalse);
    });
  });
}
