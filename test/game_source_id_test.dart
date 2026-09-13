import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_model.dart';

void main() {
  const game = Game(title: 'Crystal Vanguard (USA).zip', url: 'https://a/ct.zip', size: 1024, consoleId: 'snes');

  test('no source declared means the game belongs to the built-in addon', () {
    expect(game.sourceId, kBuiltinAddonId);
  });

  test('sourceId survives a round-trip through the cache json', () {
    final tagged = game.copyWith(sourceId: 'ultranx');
    final restored = Game.fromJson(jsonDecode(jsonEncode(tagged.toJson())) as Map<String, dynamic>);
    expect(restored.sourceId, 'ultranx');
    expect(restored.title, game.title);
    expect(restored.url, game.url);
    expect(restored.consoleId, game.consoleId);
  });

  test('toJson emits the field', () {
    expect(game.copyWith(sourceId: 'ultranx').toJson()['sourceId'], 'ultranx');
  });

  test('old cache written without the field degrades to the built-in addon', () {
    final old = {'title': 'a.zip', 'url': 'https://a/a.zip', 'size': 1, 'consoleId': 'snes'};
    expect(Game.fromJson(old).sourceId, kBuiltinAddonId);
  });

  test('copyWith replaces the source without touching other fields', () {
    final tagged = game.copyWith(sourceId: 'ultranx');
    expect(tagged.sourceId, 'ultranx');
    expect(tagged.title, game.title);
    expect(tagged.size, game.size);
  });

  test('copyWith without sourceId preserves the existing source', () {
    final tagged = game.copyWith(sourceId: 'ultranx');
    expect(tagged.copyWith(size: 2048).sourceId, 'ultranx');
  });
}
