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
}
