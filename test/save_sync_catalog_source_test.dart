import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/catalog_source.dart';

void main() {
  test('the default is the repo folder on main, read raw', () {
    expect(defaultCatalogBase, 'https://raw.githubusercontent.com/hiitsgabe/retro_toolbox/main/save_recipes/');
  });

  group('normalizeCatalogUrl', () {
    test('https gains a trailing slash and loses surrounding spaces', () {
      expect(normalizeCatalogUrl('  https://example.com/r  '), 'https://example.com/r/');
      expect(normalizeCatalogUrl('https://example.com/r/'), 'https://example.com/r/');
    });

    test('anything that is not an https address is refused', () {
      expect(normalizeCatalogUrl('http://example.com/r'), isNull);
      expect(normalizeCatalogUrl('example.com/r'), isNull);
      expect(normalizeCatalogUrl('https://'), isNull);
      expect(normalizeCatalogUrl(''), isNull);
    });
  });

  group('resolveCatalogBase', () {
    test('the setting wins over the define, the define over the default', () {
      expect(resolveCatalogBase(setting: 'https://a.example/x', define: 'https://b.example/y'), 'https://a.example/x/');
      expect(resolveCatalogBase(setting: null, define: 'https://b.example/y'), 'https://b.example/y/');
      expect(resolveCatalogBase(setting: null), defaultCatalogBase);
    });

    test('an unusable value is skipped, never used', () {
      expect(resolveCatalogBase(setting: 'http://a.example/x', define: ''), defaultCatalogBase);
      expect(resolveCatalogBase(setting: '', define: 'nope'), defaultCatalogBase);
    });
  });

  test('two bases never share a cache folder, and one base always gets the same one', () {
    final a = catalogCacheDir('/support', 'https://a.example/x/').path;
    final b = catalogCacheDir('/support', 'https://b.example/y/').path;
    expect(a, isNot(b));
    expect(catalogCacheDir('/support', 'https://a.example/x/').path, a);
    expect(a, startsWith('/support/save_sync/catalog/'));
    expect(a.split('/').last, hasLength(16));
  });
}
