import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_matcher.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';

void main() {
  group('launchboxTitleKey', () {
    test('a trailing article moves to the front, before the subtitle', () {
      expect(launchboxTitleKey('Legend of Zelda, The - A Link to the Past (USA)'), 'The Legend of Zelda - A Link to the Past');
      expect(launchboxTitleKey('Simpsons, The'), 'The Simpsons');
      expect(launchboxTitleKey('Quest for Glory, A: Shadows (Europe) (En,De)'), 'A Quest for Glory: Shadows');
      expect(launchboxTitleKey('Unknown Planet, An'), 'An Unknown Planet');
    });

    test('only a capitalized article that ends the name or its main title moves', () {
      expect(launchboxTitleKey('Simpsons, the'), 'Simpsons, the');
      expect(launchboxTitleKey('Plan, A or B'), 'Plan, A or B');
    });

    test('"&" reads as "and"', () {
      expect(launchboxTitleKey('Asterix & Obelix (Europe)'), 'Asterix and Obelix');
    });

    test('a title without an article only loses its bracket groups', () {
      expect(launchboxTitleKey('Super Metroid (Japan, USA) (En,Ja) [!]'), 'Super Metroid');
      expect(launchboxTitleKey('Super Metroid'), 'Super Metroid');
    });
  });

  group('matchLaunchboxIds', () {
    const games = [
      LaunchboxGame(id: 10, name: 'The Legend of Zelda: A Link to the Past', alternateNames: ['Zelda no Densetsu: Kamigami no Triforce']),
      LaunchboxGame(id: 20, name: 'Super Metroid'),
      LaunchboxGame(id: 30, name: 'Kalo Dorm Run'),
      LaunchboxGame(id: 40, name: 'Game 3'),
      LaunchboxGame(id: 50, name: 'Twin Name', ratingCount: 3),
      LaunchboxGame(id: 51, name: 'Twin Name', ratingCount: 90),
      LaunchboxGame(id: 52, name: 'Twin Name'),
    ];

    test('exact name, after the article move and normalizing', () async {
      expect(await matchLaunchboxIds(['Legend of Zelda, The - A Link to the Past (USA)', 'Super Metroid (Japan, USA) (En,Ja)'], games), [10, 20]);
    });

    test('alternate name', () async {
      expect(await matchLaunchboxIds(['Zelda no Densetsu - Kamigami no Triforce (Japan)'], games), [10]);
    });

    test('a near miss still matches through the fuzzy pass', () async {
      expect(await matchLaunchboxIds(['Kalo: Dorm Run - Game of the Year Edition (USA)'], games), [30]);
    });

    test('sequel numbers stay apart', () async {
      expect(await matchLaunchboxIds(['Game 2 (USA)'], games), [null]);
    });

    test('two games with the same name resolve to the one with more votes', () async {
      expect(await matchLaunchboxIds(['Twin Name (USA)'], games), [51]);
      expect(await matchLaunchboxIds(['Twin Name (USA)'], games.reversed.toList()), [51]);
    });

    test('an unmatched title is null and the list keeps input order', () async {
      expect(await matchLaunchboxIds(['Nothing Like It (USA)', 'Super Metroid (USA)', 'Twin Name', 'Also Missing'], games), [null, 20, 51, null]);
    });
  });
}
