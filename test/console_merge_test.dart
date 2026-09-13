import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

Console _console(String id, List<String> urls, {String? regex, Map<String, dynamic>? auth, String? name}) =>
    Console(id: id, name: name ?? id, urls: urls, regex: regex, auth: auth);

void main() {
  test('empty list yields empty catalog', () {
    final merged = mergeCatalogs(const []);
    expect(merged.consoles, isEmpty);
    expect(merged.sources, isEmpty);
    expect(merged.isEmpty, isTrue);
  });

  test('single addon: consoles pass through and each source carries the addon id', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'])}),
    ]);
    expect(merged.consoles.keys, ['snes']);
    expect(merged.consoles['snes']!.urls, ['https://a/']);
    expect(merged.sources['snes']!.single.addonId, 'one');
    expect(merged.sources['snes']!.single.url, 'https://a/');
  });

  test('console declared only by the second addon is included', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'])}),
      (addonId: 'two', consoles: {'nes': _console('nes', ['https://b/'])}),
    ]);
    expect(merged.consoles.keys, containsAll(['snes', 'nes']));
    expect(merged.sources['nes']!.single.addonId, 'two');
  });

  test('same console in both addons: metadata comes from the FIRST addon', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'], name: 'Super Nintendo', regex: 'FROM ONE')}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://b/'], name: 'SNES', regex: 'FROM TWO')}),
    ]);
    expect(merged.consoles['snes']!.name, 'Super Nintendo');
    expect(merged.consoles['snes']!.regex, 'FROM ONE');
  });

  test('same console in both addons: urls concatenate in addon order', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/', 'https://a2/'])}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://b/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://a/', 'https://a2/', 'https://b/']);
  });

  test('duplicate url across addons enters once, from the first', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://same/'])}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://same/', 'https://other/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://same/', 'https://other/']);
    expect(merged.sources['snes']!.map((f) => f.addonId), ['one', 'two']);
  });

  test('duplicate url within the same addon enters once', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/', 'https://a/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://a/']);
  });

  test('each source auth comes from the addon that declared that url', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'], auth: {'token': 'unused', 'cookies': true})}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://b/'], auth: {'type': 'ia_s3'})}),
    ]);
    final sources = merged.sources['snes']!;
    expect(sources[0].auth!['cookies'], true);
    expect(sources[1].auth!['type'], 'ia_s3');
  });

  test('invariant: console urls match source urls in the same order', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/']), 'nes': _console('nes', ['https://n1/', 'https://n2/'])}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://b/'])}),
    ]);
    for (final id in merged.consoles.keys) {
      expect(merged.sources[id]!.map((f) => f.url).toList(), merged.consoles[id]!.urls, reason: 'console $id');
    }
  });

  test('console with no urls enters with an empty source list', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', const [])}),
    ]);
    expect(merged.consoles.containsKey('snes'), isTrue);
    expect(merged.sources['snes'], isEmpty);
  });

  test('addon with no consoles does not affect others', () {
    final merged = mergeCatalogs([
      (addonId: 'empty', consoles: const {}),
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'])}),
    ]);
    expect(merged.consoles.keys, ['snes']);
    expect(merged.sources['snes']!.single.addonId, 'one');
  });

  test('withUrls replaces urls without losing any other field', () {
    // Every field is the OPPOSITE of its constructor default, so a dropped
    // `withUrls` line cannot be masked by the constructor restoring the default.
    const full = Console(
      id: 'snes',
      name: 'Super Nintendo',
      urls: ['https://a/'],
      regex: r'\.sfc$',
      boxarts: {'url': 'https://box/'},
      fileFormat: ['sfc', 'smc'],
      romsFolder: 'roms/snes',
      shouldUnzip: true,
      extractContents: false,
      shouldFilterUsa: false,
      usaRegex: r'\(USA\)',
      shouldDecompressNsz: true,
      ignoreExtensionFiltering: true,
      downloadUrl: 'https://download/',
      auth: {'type': 'cookies'},
      listUrl: 'https://list/',
      listJsonFileLocation: 'items',
      listItemId: 'title',
      listSystems: true,
      added: true,
      convert3dsToCia: true,
    );

    final copy = full.withUrls(['https://b/', 'https://c/']);

    expect(copy.urls, ['https://b/', 'https://c/']);
    expect(copy.id, full.id);
    expect(copy.name, full.name);
    expect(copy.regex, full.regex);
    expect(copy.boxarts, full.boxarts);
    expect(copy.fileFormat, full.fileFormat);
    expect(copy.romsFolder, full.romsFolder);
    expect(copy.shouldUnzip, full.shouldUnzip);
    expect(copy.extractContents, full.extractContents);
    expect(copy.shouldFilterUsa, full.shouldFilterUsa);
    expect(copy.usaRegex, full.usaRegex);
    expect(copy.shouldDecompressNsz, full.shouldDecompressNsz);
    expect(copy.ignoreExtensionFiltering, full.ignoreExtensionFiltering);
    expect(copy.downloadUrl, full.downloadUrl);
    expect(copy.auth, full.auth);
    expect(copy.listUrl, full.listUrl);
    expect(copy.listJsonFileLocation, full.listJsonFileLocation);
    expect(copy.listItemId, full.listItemId);
    expect(copy.listSystems, full.listSystems);
    expect(copy.added, full.added);
    expect(copy.convert3dsToCia, full.convert3dsToCia);
  });
}
