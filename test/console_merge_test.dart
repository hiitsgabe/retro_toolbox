import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

Console _console(String id, List<String> urls, {String? regex, Map<String, dynamic>? auth, String? name}) =>
    Console(id: id, name: name ?? id, urls: urls, regex: regex, auth: auth);

void main() {
  test('lista vazia dá catálogo vazio', () {
    final merged = mergeCatalogs(const []);
    expect(merged.consoles, isEmpty);
    expect(merged.sources, isEmpty);
    expect(merged.isEmpty, isTrue);
  });

  test('um addon só: os consoles saem iguais e cada fonte carrega o id do addon', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'])}),
    ]);
    expect(merged.consoles.keys, ['snes']);
    expect(merged.consoles['snes']!.urls, ['https://a/']);
    expect(merged.sources['snes']!.single.addonId, 'um');
    expect(merged.sources['snes']!.single.url, 'https://a/');
  });

  test('console que só o segundo addon declara entra do mesmo jeito', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'])}),
      (addonId: 'dois', consoles: {'nes': _console('nes', ['https://b/'])}),
    ]);
    expect(merged.consoles.keys, containsAll(['snes', 'nes']));
    expect(merged.sources['nes']!.single.addonId, 'dois');
  });

  test('mesmo console nos dois: os metadados são do PRIMEIRO addon', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'], name: 'Super Nintendo', regex: 'DO UM')}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://b/'], name: 'SNES', regex: 'DO DOIS')}),
    ]);
    expect(merged.consoles['snes']!.name, 'Super Nintendo');
    expect(merged.consoles['snes']!.regex, 'DO UM');
  });

  test('mesmo console nos dois: as urls concatenam na ordem dos addons', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/', 'https://a2/'])}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://b/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://a/', 'https://a2/', 'https://b/']);
  });

  test('url repetida entre dois addons entra uma vez só, do primeiro', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://mesma/'])}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://mesma/', 'https://outra/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://mesma/', 'https://outra/']);
    expect(merged.sources['snes']!.map((f) => f.addonId), ['um', 'dois']);
  });

  test('url repetida dentro do mesmo addon entra uma vez só', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/', 'https://a/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://a/']);
  });

  test('a auth de cada fonte é a do addon que declarou AQUELA url', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'], auth: {'token': 'nao usado', 'cookies': true})}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://b/'], auth: {'type': 'ia_s3'})}),
    ]);
    final fontes = merged.sources['snes']!;
    expect(fontes[0].auth!['cookies'], true);
    expect(fontes[1].auth!['type'], 'ia_s3');
  });

  test('o invariante: as urls do console são as urls das fontes, na mesma ordem', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/']), 'nes': _console('nes', ['https://n1/', 'https://n2/'])}),
      (addonId: 'dois', consoles: {'snes': _console('snes', ['https://b/'])}),
    ]);
    for (final id in merged.consoles.keys) {
      expect(merged.sources[id]!.map((f) => f.url).toList(), merged.consoles[id]!.urls, reason: 'console $id');
    }
  });

  test('console sem url nenhuma entra com lista de fontes vazia', () {
    final merged = mergeCatalogs([
      (addonId: 'um', consoles: {'snes': _console('snes', const [])}),
    ]);
    expect(merged.consoles.containsKey('snes'), isTrue);
    expect(merged.sources['snes'], isEmpty);
  });

  test('addon sem console nenhum não atrapalha os outros', () {
    final merged = mergeCatalogs([
      (addonId: 'vazio', consoles: const {}),
      (addonId: 'um', consoles: {'snes': _console('snes', ['https://a/'])}),
    ]);
    expect(merged.consoles.keys, ['snes']);
    expect(merged.sources['snes']!.single.addonId, 'um');
  });

  test('withUrls troca as urls e não perde nenhum dos outros campos', () {
    // Todo campo aqui vale o CONTRÁRIO do padrão do construtor. Se algum
    // valesse o padrão, apagar a linha correspondente do `withUrls` passaria
    // despercebido: o construtor repõe o mesmo valor e o teste segue verde.
    const cheio = Console(
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
      downloadUrl: 'https://baixa/',
      auth: {'type': 'cookies'},
      listUrl: 'https://lista/',
      listJsonFileLocation: 'items',
      listItemId: 'title',
      listSystems: true,
      added: true,
      convert3dsToCia: true,
    );

    final copia = cheio.withUrls(['https://b/', 'https://c/']);

    expect(copia.urls, ['https://b/', 'https://c/']);
    expect(copia.id, cheio.id);
    expect(copia.name, cheio.name);
    expect(copia.regex, cheio.regex);
    expect(copia.boxarts, cheio.boxarts);
    expect(copia.fileFormat, cheio.fileFormat);
    expect(copia.romsFolder, cheio.romsFolder);
    expect(copia.shouldUnzip, cheio.shouldUnzip);
    expect(copia.extractContents, cheio.extractContents);
    expect(copia.shouldFilterUsa, cheio.shouldFilterUsa);
    expect(copia.usaRegex, cheio.usaRegex);
    expect(copia.shouldDecompressNsz, cheio.shouldDecompressNsz);
    expect(copia.ignoreExtensionFiltering, cheio.ignoreExtensionFiltering);
    expect(copia.downloadUrl, cheio.downloadUrl);
    expect(copia.auth, cheio.auth);
    expect(copia.listUrl, cheio.listUrl);
    expect(copia.listJsonFileLocation, cheio.listJsonFileLocation);
    expect(copia.listItemId, cheio.listItemId);
    expect(copia.listSystems, cheio.listSystems);
    expect(copia.added, cheio.added);
    expect(copia.convert3dsToCia, cheio.convert3dsToCia);
  });
}
