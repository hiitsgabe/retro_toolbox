import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/title_catalog.dart';

/// A bundle holding one document, or none.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.body);

  final String? body;

  @override
  Future<ByteData> load(String key) async => throw StateError('no asset $key');

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final b = body;
    if (b == null) throw StateError('no asset $key');
    return b;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(TitleCatalog.reset);

  test('ids are keyed in the case the save folders use', () {
    final map = parseTitles('''
      [ {"name": "Alpha Title", "id": "0100000000abc000", "image": "https://art.example/a.png"} ]
    ''');
    expect(map['0100000000ABC000']?.name, 'Alpha Title');
    expect(map['0100000000ABC000']?.image, 'https://art.example/a.png');
  });

  test('a record with no art is still a name', () {
    final map = parseTitles('[ {"name": "Beta Title", "id": "0100000000DEF000", "image": ""} ]');
    expect(map['0100000000DEF000']?.name, 'Beta Title');
    expect(map['0100000000DEF000']?.image, isNull);
  });

  test('a nameless or idless record is skipped, not guessed at', () {
    final map = parseTitles('''
      [ {"name": "", "id": "0100000000DEF000"},
        {"id": "0100000000AAA000"},
        {"name": "Gamma Title"},
        "not even a record" ]
    ''');
    expect(map, isEmpty);
  });

  test('a title listed once per region keeps the first name', () {
    final map = parseTitles('''
      [ {"name": "Delta Title", "id": "0100000000ABC000"},
        {"name": "Delta Title (Other Region)", "id": "0100000000ABC000"} ]
    ''');
    expect(map['0100000000ABC000']?.name, 'Delta Title');
  });

  test('a document that is not a list reads as no catalog', () {
    expect(parseTitles('{"titles": []}'), isEmpty);
  });

  test('the catalog is read from the bundle once', () async {
    final bundle = _Bundle('[ {"name": "Alpha Title", "id": "0100000000ABC000"} ]');
    final first = await TitleCatalog.load(bundle: bundle);
    expect(first['0100000000ABC000']?.name, 'Alpha Title');
    // A second caller gets the same parse, not another one: the asset is
    // megabytes and nothing about it changes while the app runs.
    expect(identical(first, await TitleCatalog.load(bundle: _Bundle(null))), isTrue);
  });

  test('a build with no catalog leaves the ids alone instead of failing', () async {
    expect(await TitleCatalog.load(bundle: _Bundle(null)), isEmpty);
  });
}
