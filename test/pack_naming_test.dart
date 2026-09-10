import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

void main() {
  group('stripRomExtension', () {
    test('tira a extensão de ROM', () {
      expect(stripRomExtension('Chrono Trigger (USA).sfc'), 'Chrono Trigger (USA)');
      expect(stripRomExtension('Chrono Trigger (USA).zip'), 'Chrono Trigger (USA)');
      expect(stripRomExtension('Chrono Trigger (USA).ZIP'), 'Chrono Trigger (USA)');
    });

    test('não tira o que não é extensão de ROM', () {
      expect(stripRomExtension('Chrono Trigger (USA).txt'), 'Chrono Trigger (USA).txt');
      expect(stripRomExtension('Vol. 3'), 'Vol. 3');
    });

    test('prefere a extensão mais longa', () {
      // .gbc e .gb casam os dois; a mais longa é a certa.
      expect(stripRomExtension('Zelda.gbc'), 'Zelda');
    });
  });

  group('norm', () {
    test('baixa a caixa e troca pontuação por espaço', () {
      expect(norm('Chrono Trigger (USA)'), 'chrono trigger (usa)');
      expect(norm('Zero 4 Champ RR-Z (Japan)'), 'zero 4 champ rr z (japan)');
    });

    test('expande o e comercial', () {
      expect(norm('Dig & Spike'), 'dig and spike');
    });

    test('tira acento', () {
      expect(norm('Pokémon Rojo'), 'pokemon rojo');
      expect(norm('Astérix & Obélix'), 'asterix and obelix');
    });

    test('tira a extensão antes de normalizar', () {
      expect(norm('Chrono Trigger (USA).sfc'), 'chrono trigger (usa)');
    });

    test('preserva as tags de região e revisão', () {
      expect(norm('Chrono Trigger (USA) (Rev 1) [!]'), 'chrono trigger (usa) (rev 1) []');
    });

    test('nome só de pontuação vira vazio', () {
      expect(norm('---'), '');
      expect(norm(''), '');
    });
  });

  group('displayTitle', () {
    test('preserva a caixa original', () {
      expect(displayTitle('Chrono Trigger (USA)'), 'Chrono Trigger');
    });

    test('move o artigo do fim para a frente sem mexer no resto', () {
      expect(displayTitle('Legend of Zelda, The (USA)'), 'The Legend of Zelda');
      expect(displayTitle('Blue Crystalrod, The (Japan)'), 'The Blue Crystalrod');
    });

    test('preserva acento e pontuação', () {
      expect(displayTitle('Pokémon Rojo (Spain).gb'), 'Pokémon Rojo');
      expect(displayTitle('Super Mario World 2 - Yoshi\'s Island (USA)'),
          'Super Mario World 2 - Yoshi\'s Island');
    });

    test('nome que é só tag vira vazio', () {
      expect(displayTitle('(USA)'), '');
    });

    test('tira vírgula sobrando na ponta', () {
      expect(displayTitle('Addams Family, (USA)'), 'Addams Family');
    });
  });

  group('canon', () {
    test('descarta tags de região e revisão', () {
      expect(canon('Chrono Trigger (USA) (Rev 1)'), 'chrono trigger');
      expect(canon('Chrono Trigger (Japan) [T+Eng]'), 'chrono trigger');
    });

    test('move o artigo antes de normalizar', () {
      expect(canon('Legend of Zelda, The (USA)'), 'the legend of zelda');
    });

    test('regiões diferentes do mesmo jogo dão a mesma chave', () {
      expect(canon('Super Mario World (USA)'), canon('Super Mario World (Europe)'));
    });

    test('nome que é só tag vira chave vazia', () {
      expect(canon('(USA)'), '');
    });
  });
}
