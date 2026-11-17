import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_images.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';

const _front = LaunchboxImageType.boxFront;

LaunchboxImage _img(String file, [String? region, LaunchboxImageType type = _front]) => LaunchboxImage(type, file, region);

void main() {
  group('pickLaunchboxImage', () {
    final all = [
      _img('any.jpg', 'Germany'),
      _img('none.jpg'),
      _img('world.jpg', 'World'),
      _img('na.jpg', 'North America'),
      _img('eu.jpg', 'Europe'),
      _img('jp.jpg', 'Japan'),
    ];

    test('the game region wins', () {
      expect(pickLaunchboxImage(all, _front, 'Europe')?.file, 'eu.jpg');
      expect(pickLaunchboxImage(all, _front, 'Japan')?.file, 'jp.jpg');
    });

    test('USA picks North America, or United States', () {
      expect(pickLaunchboxImage(all, _front, 'USA')?.file, 'na.jpg');
      expect(pickLaunchboxImage([_img('any.jpg', 'Germany'), _img('us.jpg', 'United States')], _front, 'USA')?.file, 'us.jpg');
    });

    test('then North America, then World, then no region, then any', () {
      expect(pickLaunchboxImage(all, _front, 'Brazil')?.file, 'na.jpg');
      expect(pickLaunchboxImage(all.where((i) => i.file != 'na.jpg').toList(), _front, 'Brazil')?.file, 'world.jpg');
      expect(pickLaunchboxImage([_img('any.jpg', 'Germany'), _img('none.jpg')], _front, 'Brazil')?.file, 'none.jpg');
      expect(pickLaunchboxImage([_img('any.jpg', 'Germany')], _front, 'Brazil')?.file, 'any.jpg');
    });

    test('only images of the asked type count; a missing type is null', () {
      final images = [_img('logo.png', 'Europe', LaunchboxImageType.clearLogo), _img('na.jpg', 'North America')];
      expect(pickLaunchboxImage(images, LaunchboxImageType.clearLogo, 'USA')?.file, 'logo.png');
      expect(pickLaunchboxImage(images, LaunchboxImageType.fanart, 'USA'), isNull);
      expect(pickLaunchboxImage(const [], _front, 'USA'), isNull);
    });
  });

  test('launchboxImagesOf keeps the preference order, ties in file order', () {
    final shots = [
      _img('a.jpg', null, LaunchboxImageType.screenshot),
      _img('b.jpg', 'Europe', LaunchboxImageType.screenshot),
      _img('front.jpg', 'Europe'),
      _img('c.jpg', null, LaunchboxImageType.screenshot),
      _img('d.jpg', 'North America', LaunchboxImageType.screenshot),
    ];
    expect([for (final i in launchboxImagesOf(shots, LaunchboxImageType.screenshot, 'Europe')) i.file], ['b.jpg', 'd.jpg', 'a.jpg', 'c.jpg']);
  });

  group('heroBackground', () {
    const fanart = LaunchboxImage(LaunchboxImageType.fanart, 'fan.jpg');
    const shot = LaunchboxImage(LaunchboxImageType.screenshot, 'shot.jpg');
    LaunchboxGame lb(List<LaunchboxImage> images) => LaunchboxGame(id: 1, name: 'G', images: images);

    test('fanart first', () {
      expect(heroBackground(lb([shot, fanart]), 'USA', 'https://box'), (url: fanart.url, blur: false));
    });

    test('else a gameplay screenshot', () {
      expect(heroBackground(lb([shot]), 'USA', 'https://box'), (url: shot.url, blur: false));
    });

    test('else the box art, blurred', () {
      expect(heroBackground(lb(const []), 'USA', 'https://box'), (url: 'https://box', blur: true));
      expect(heroBackground(null, 'USA', 'https://box'), (url: 'https://box', blur: true));
    });

    test('else nothing', () {
      expect(heroBackground(null, 'USA', null), isNull);
      expect(heroBackground(lb(const [LaunchboxImage(LaunchboxImageType.titleScreen, 't.jpg')]), 'USA', null), isNull);
    });
  });
}
