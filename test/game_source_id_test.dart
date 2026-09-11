import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_model.dart';

void main() {
  const jogo = Game(title: 'Chrono Trigger (USA).zip', url: 'https://a/ct.zip', size: 1024, consoleId: 'snes');

  test('sem fonte declarada, o jogo é do addon embutido', () {
    expect(jogo.sourceId, kBuiltinAddonId);
  });

  test('o sourceId sobrevive à ida e volta pelo json do cache', () {
    final marcado = jogo.copyWith(sourceId: 'ultranx');
    final volta = Game.fromJson(jsonDecode(jsonEncode(marcado.toJson())) as Map<String, dynamic>);
    expect(volta.sourceId, 'ultranx');
    expect(volta.title, jogo.title);
    expect(volta.url, jogo.url);
    expect(volta.consoleId, jogo.consoleId);
  });

  test('toJson emite o campo', () {
    expect(jogo.copyWith(sourceId: 'ultranx').toJson()['sourceId'], 'ultranx');
  });

  test('cache antigo, escrito sem o campo, degrada para o embutido', () {
    final antigo = {'title': 'a.zip', 'url': 'https://a/a.zip', 'size': 1, 'consoleId': 'snes'};
    expect(Game.fromJson(antigo).sourceId, kBuiltinAddonId);
  });

  test('copyWith troca a fonte sem mexer no resto', () {
    final marcado = jogo.copyWith(sourceId: 'ultranx');
    expect(marcado.sourceId, 'ultranx');
    expect(marcado.title, jogo.title);
    expect(marcado.size, jogo.size);
  });

  test('copyWith sem sourceId preserva a fonte que já estava', () {
    final marcado = jogo.copyWith(sourceId: 'ultranx');
    expect(marcado.copyWith(size: 2048).sourceId, 'ultranx');
  });
}
