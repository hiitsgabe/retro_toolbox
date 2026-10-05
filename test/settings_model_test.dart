import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/settings_model.dart';

void main() {
  test('useOnScreenKeyboard defaults off and survives a JSON round trip', () {
    expect(const AppSettings().useOnScreenKeyboard, isFalse);
    expect(AppSettings.fromJson(const {}).useOnScreenKeyboard, isFalse);
    final on = const AppSettings().copyWith(useOnScreenKeyboard: true);
    expect(AppSettings.fromJson(on.toJson()).useOnScreenKeyboard, isTrue);
  });
}
