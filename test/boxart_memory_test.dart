import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/utils/image_memory.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';

void main() {
  test('thumbnails decode at the larger box side in device pixels, rounded up to 64', () {
    expect(thumbnailDecodeWidth(40, 40, 1.5), 64); // 60 px
    expect(thumbnailDecodeWidth(150, 200, 1.0), 256); // 200 px
    expect(thumbnailDecodeWidth(150, 200, 2.0), 448); // 400 px
    expect(thumbnailDecodeWidth(0, 0, 1.0), 64);
  });

  test('devices get a smaller image cache than the 100 MB default', () {
    final cache = ImageCache();
    capImageCache(cache);
    expect(cache.maximumSizeBytes, 48 << 20);
    expect(cache.maximumSize, 300);
  });

  testWidgets('a box art thumbnail is decoded at its on-screen size, not full size', (t) async {
    const game = Game(title: 'a.zip', url: 'https://h/a.zip', size: 1, consoleId: 'c', details: GameDetails(boxart: 'https://h/a.png'));
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 2),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SizedBox(width: 150, height: 200, child: const GameBoxart(game: game))),
      ),
    ));
    final image = t.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.memCacheWidth, 448);
  });
}
