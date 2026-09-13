import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

void main() {
  group('stripRomExtension', () {
    test('strips a ROM extension', () {
      expect(stripRomExtension('Crystal Vanguard (USA).sfc'), 'Crystal Vanguard (USA)');
      expect(stripRomExtension('Crystal Vanguard (USA).zip'), 'Crystal Vanguard (USA)');
      expect(stripRomExtension('Crystal Vanguard (USA).ZIP'), 'Crystal Vanguard (USA)');
    });

    test('does not strip what is not a ROM extension', () {
      expect(stripRomExtension('Crystal Vanguard (USA).txt'), 'Crystal Vanguard (USA).txt');
      expect(stripRomExtension('Vol. 3'), 'Vol. 3');
    });

    test('prefers the longest extension', () {
      // .gbc and .gb both match; the longer one is right.
      expect(stripRomExtension('Kaelis.gbc'), 'Kaelis');
    });
  });

  group('norm', () {
    test('lowercases and turns punctuation into space', () {
      expect(norm('Crystal Vanguard (USA)'), 'crystal vanguard (usa)');
      expect(norm('Reso 4 Kkesv HQ-H (Japan)'), 'reso 4 kkesv hq h (japan)');
    });

    test('expands the ampersand', () {
      expect(norm('Zuf & Lgari'), 'zuf and lgari');
    });

    test('strips accents', () {
      expect(norm('Prismón Rojo'), 'prismon rojo');
      expect(norm('Aqtúveh & Atérap'), 'aqtuveh and aterap');
    });

    test('strips the extension before normalizing', () {
      expect(norm('Crystal Vanguard (USA).sfc'), 'crystal vanguard (usa)');
    });

    test('preserves region and revision tags', () {
      // `!` is forbidden punctuation and becomes a space; a lone space is not
      // collapsed by `\s+`, so the bracket keeps the space inside. This mirrors
      // the builder's `norm`, so `[ ]` over `[]` is parity, not a typo.
      expect(norm('Crystal Vanguard (USA) (Rev 1) [!]'), 'crystal vanguard (usa) (rev 1) [ ]');
    });

    test('a punctuation-only name becomes empty', () {
      expect(norm('---'), '');
      expect(norm(''), '');
    });
  });

  group('displayTitle', () {
    test('preserves the original case', () {
      expect(displayTitle('Crystal Vanguard (USA)'), 'Crystal Vanguard');
    });

    test('moves the trailing article to the front without touching the rest', () {
      expect(displayTitle('Legend of Kaelis, The (USA)'), 'The Legend of Kaelis');
      expect(displayTitle('Zxia Gztqfevzem, The (Japan)'), 'The Zxia Gztqfevzem');
    });

    test('preserves accents and punctuation', () {
      expect(displayTitle('Prismón Rojo (Spain).gb'), 'Prismón Rojo');
      expect(displayTitle('Super Pixel World 2 - Yuki\'s Island (USA)'),
          'Super Pixel World 2 - Yuki\'s Island');
    });

    test('a tag-only name becomes empty', () {
      expect(displayTitle('(USA)'), '');
    });

    test('strips a trailing comma', () {
      expect(displayTitle('Awsoht Dupalj, (USA)'), 'Awsoht Dupalj');
    });
  });

  group('canon', () {
    test('drops region and revision tags', () {
      expect(canon('Crystal Vanguard (USA) (Rev 1)'), 'crystal vanguard');
      expect(canon('Crystal Vanguard (Japan) [T+Eng]'), 'crystal vanguard');
    });

    test('moves the article before normalizing', () {
      expect(canon('Legend of Kaelis, The (USA)'), 'the legend of kaelis');
    });

    test('different regions of the same game give the same key', () {
      expect(canon('Super Pixel World (USA)'), canon('Super Pixel World (Europe)'));
    });

    test('a tag-only name becomes an empty key', () {
      expect(canon('(USA)'), '');
    });
  });
}
