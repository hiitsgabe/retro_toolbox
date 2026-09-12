import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Prova que a porta Dart de `norm`, `displayTitle` e `canon` concorda com o
/// builder Python caso a caso, sobre nomes reais do DAT do SNES mais uma lista
/// de casos difíceis. O golden é gerado por `tool/dump_naming_golden.py`.
///
/// Se este teste quebrar depois de você mexer no builder, a resposta certa
/// quase sempre é regerar o golden e alinhar o Dart, não relaxar o teste.
void main() {
  late List<Map<String, dynamic>> cases;

  setUpAll(() {
    final raw = File('test/fixtures/naming_golden.json').readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    cases = (decoded['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThan(50), reason: 'golden vazio ou truncado');
  });

  test('norm concorda com o builder em todos os casos do golden', () {
    for (final c in cases) {
      expect(norm(c['input'] as String), c['norm'],
          reason: 'norm divergiu em "${c['input']}"');
    }
  });

  test('displayTitle concorda com o builder em todos os casos do golden', () {
    for (final c in cases) {
      expect(displayTitle(c['input'] as String), c['displayTitle'],
          reason: 'displayTitle divergiu em "${c['input']}"');
    }
  });

  test('canon concorda com o builder em todos os casos do golden', () {
    for (final c in cases) {
      expect(canon(c['input'] as String), c['canon'],
          reason: 'canon divergiu em "${c['input']}"');
    }
  });
}
