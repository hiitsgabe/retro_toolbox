import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';

LaunchboxGame? game(Map<String, String> extra) => launchboxGameFromFields({'DatabaseID': '7', 'Name': 'Chrono Trigger', ...extra});

void main() {
  group('launchboxGameFromFields', () {
    test('ReleaseDate with a time suffix gives yyyymmdd', () {
      expect(game({'ReleaseDate': '1991-08-23T00:00:00-07:00'})!.releaseDate, 19910823);
    });

    test('ReleaseYear alone gives yyyy0000', () {
      expect(game({'ReleaseYear': '1994'})!.releaseDate, 19940000);
    });

    test('ReleaseDate beats ReleaseYear', () {
      expect(game({'ReleaseYear': '1994', 'ReleaseDate': '1995-03-11'})!.releaseDate, 19950311);
    });

    test('an unparsable date is null', () {
      expect(game({'ReleaseDate': 'soon'})!.releaseDate, isNull);
    });

    test('missing DatabaseID or Name gives null', () {
      expect(launchboxGameFromFields({'Name': 'X'}), isNull);
      expect(launchboxGameFromFields({'DatabaseID': 'abc', 'Name': 'X'}), isNull);
      expect(launchboxGameFromFields({'DatabaseID': '1'}), isNull);
      expect(launchboxGameFromFields({'DatabaseID': '1', 'Name': '  '}), isNull);
    });

    test('genres split on semicolons', () {
      expect(game({'Genres': 'Action; Role-Playing'})!.genres, ['Action', 'Role-Playing']);
      expect(game({'Genres': ''})!.genres, isEmpty);
    });

    test('Cooperative True is true, anything else false', () {
      expect(game({'Cooperative': 'True'})!.cooperative, isTrue);
      expect(game({'Cooperative': 'false'})!.cooperative, isFalse);
      expect(game({})!.cooperative, isFalse);
    });

    test('blank Developer is null', () {
      expect(game({'Developer': '   '})!.developer, isNull);
      expect(game({'Developer': 'Square'})!.developer, 'Square');
    });

    test('reads the numeric and text fields', () {
      final g = game({
        'Overview': 'Time travel.',
        'MaxPlayers': '1',
        'CommunityRating': '4.5',
        'CommunityRatingCount': '120',
        'Publisher': 'Square',
        'ESRB': 'E - Everyone',
      })!;
      expect(g.id, 7);
      expect(g.name, 'Chrono Trigger');
      expect(g.overview, 'Time travel.');
      expect(g.maxPlayers, 1);
      expect(g.rating, 4.5);
      expect(g.ratingCount, 120);
      expect(g.publisher, 'Square');
      expect(g.esrb, 'E - Everyone');
    });
  });

  group('image types', () {
    test('fromXml and fromCode map both ways', () {
      for (final t in LaunchboxImageType.values) {
        expect(LaunchboxImageType.fromXml(t.xmlName), t);
        expect(LaunchboxImageType.fromCode(t.code), t);
      }
      expect(LaunchboxImageType.fromXml('Banner'), isNull);
      expect(LaunchboxImageType.fromCode('zz'), isNull);
    });

    test('url points at the LaunchBox image host', () {
      expect(const LaunchboxImage(LaunchboxImageType.boxFront, 'a.jpg').url, 'https://images.launchbox-app.com/a.jpg');
    });
  });

  group('json', () {
    const full = LaunchboxGame(
      id: 42,
      name: 'Super Metroid',
      alternateNames: ['Metroid 3'],
      releaseDate: 19940319,
      overview: 'Line one\nline two & more',
      maxPlayers: 1,
      cooperative: true,
      rating: 4.75,
      ratingCount: 300,
      genres: ['Action', 'Platform'],
      developer: 'Nintendo R&D1',
      publisher: 'Nintendo',
      esrb: 'K-A - Kids to Adults',
      images: [
        LaunchboxImage(LaunchboxImageType.boxFront, 'f.jpg', 'North America'),
        LaunchboxImage(LaunchboxImageType.screenshot, 's.png'),
      ],
    );

    test('round trip keeps every field, including image region', () {
      final back = LaunchboxGame.fromJson(full.toJson());
      expect(back.id, 42);
      expect(back.name, 'Super Metroid');
      expect(back.alternateNames, ['Metroid 3']);
      expect(back.releaseDate, 19940319);
      expect(back.overview, 'Line one\nline two & more');
      expect(back.maxPlayers, 1);
      expect(back.cooperative, isTrue);
      expect(back.rating, 4.75);
      expect(back.ratingCount, 300);
      expect(back.genres, ['Action', 'Platform']);
      expect(back.developer, 'Nintendo R&D1');
      expect(back.publisher, 'Nintendo');
      expect(back.esrb, 'K-A - Kids to Adults');
      expect(back.images.map((i) => [i.type, i.file, i.region]), [
        [LaunchboxImageType.boxFront, 'f.jpg', 'North America'],
        [LaunchboxImageType.screenshot, 's.png', null],
      ]);
    });

    test('uses the short keys', () {
      expect(full.toJson().keys.toSet(), {'i', 'n', 'a', 'd', 'o', 'p', 'c', 'r', 'v', 'g', 'dev', 'pub', 'e', 'img'});
      expect(full.toJson()['img'], [
        ['bf', 'f.jpg', 'North America'],
        ['sg', 's.png'],
      ]);
    });

    test('null and empty fields are absent', () {
      expect(const LaunchboxGame(id: 1, name: 'Bare').toJson(), {'i': 1, 'n': 'Bare'});
    });

    test('an unknown image code is skipped', () {
      final g = LaunchboxGame.fromJson({
        'i': 1,
        'n': 'X',
        'img': [
          ['zz', 'a.jpg'],
          ['cl', 'b.png'],
        ],
      });
      expect(g.images.map((i) => i.file), ['b.png']);
    });
  });
}
