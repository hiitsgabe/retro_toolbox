import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/settings_model.dart';

void main() {
  test('useOnScreenKeyboard defaults off and survives a JSON round trip', () {
    expect(const AppSettings().useOnScreenKeyboard, isFalse);
    expect(AppSettings.fromJson(const {}).useOnScreenKeyboard, isFalse);
    final on = const AppSettings().copyWith(useOnScreenKeyboard: true);
    expect(AppSettings.fromJson(on.toJson()).useOnScreenKeyboard, isTrue);
  });

  test('resolveActiveHandler: saved choice, then catalog default', () {
    expect(resolveActiveHandler(saved: null, jsonDefault: GameHandler.chdCompress, nszEnabled: true), GameHandler.chdCompress);
    expect(resolveActiveHandler(saved: 'none', jsonDefault: GameHandler.chdCompress, nszEnabled: true), isNull);
    expect(resolveActiveHandler(saved: 'chd_compress', jsonDefault: null, nszEnabled: true), GameHandler.chdCompress);
    expect(resolveActiveHandler(saved: null, jsonDefault: GameHandler.nszDecompress, nszEnabled: false), isNull);
    expect(resolveActiveHandler(saved: 'nsz_decompress', jsonDefault: GameHandler.nszDecompress, nszEnabled: false), GameHandler.nszDecompress);
  });

  test('BaseSettings round-trips additionalHandler, and null clears it', () {
    final set = const BaseSettings().setSetting(AppSettings.additionalHandler, 'none');
    final back = BaseSettings.fromJson(set.toJson());
    expect(back.getSetting<String>(AppSettings.additionalHandler), 'none');
    expect(back.setSetting<String>(AppSettings.additionalHandler, null).getSetting<String>(AppSettings.additionalHandler), isNull);
  });
}
