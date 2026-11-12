import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/glob.dart';

void main() {
  test('* stays inside one segment', () {
    expect(Glob('*/SaveGameInfo').matches('Farm_1/SaveGameInfo'), isTrue);
    expect(Glob('*/SaveGameInfo').matches('a/b/SaveGameInfo'), isFalse);
    expect(Glob('*.sos').matches('Saves/x.sos'), isFalse);
  });

  test('** spans segments, and **/ also matches zero segments', () {
    expect(Glob('Restore_Points*/**').matches('Restore_Points1/a/b.dat'), isTrue);
    expect(Glob('**/x').matches('x'), isTrue);
    expect(Glob('**/x').matches('a/b/x'), isTrue);
  });

  test('? and character classes', () {
    expect(Glob('user[1-4].dat').matches('user3.dat'), isTrue);
    expect(Glob('user[1-4].dat').matches('user5.dat'), isFalse);
    expect(Glob('user[!1-4].dat').matches('user5.dat'), isTrue);
    expect(Glob('user?.dat').matches('user12.dat'), isFalse);
  });

  test('regex characters in a pattern are literal', () {
    expect(Glob('a+b(c).txt').matches('a+b(c).txt'), isTrue);
    expect(Glob('a.b').matches('aXb'), isFalse);
  });

  test('expandPlaceholders puts the unit key in, literally', () {
    expect(Glob(expandPlaceholders('*/{folder}', 'Farm_1')).matches('Farm_1/Farm_1'), isTrue);
    expect(Glob(expandPlaceholders('*/{folder}', 'Farm_1')).matches('Farm_1/Farm_2'), isFalse);
    expect(Glob(expandPlaceholders('{file}.new', 'user1.dat')).matches('user1.dat.new'), isTrue);
    expect(Glob(expandPlaceholders('*/{folder}', 'Odd[1]*')).matches('Odd[1]*/Odd[1]*'), isTrue);
    expect(Glob(expandPlaceholders('*/{folder}', 'Odd[1]*')).matches('Odd[1]*/Odd1x'), isFalse);
  });
}
