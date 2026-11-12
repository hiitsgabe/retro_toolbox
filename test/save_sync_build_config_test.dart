import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Google client id travels from a CI secret (or a local file) through
/// `--dart-define` to `String.fromEnvironment`; a name that differs anywhere
/// on the way silently hides Google Drive in that build.
void main() {
  const name = 'GDRIVE_SERVER_CLIENT_ID';

  test('the app reads the client id under the name the builds pass', () {
    expect(File('lib/services/save_sync/google_auth.dart').readAsStringSync(), contains("String.fromEnvironment('$name')"));
  });

  test('every Android build in CI passes the client id from the secret', () {
    for (final f in ['.github/workflows/release.yml', '.eas/workflows/play-store.yml']) {
      final builds = File(f).readAsLinesSync().where((l) => RegExp(r'flutter build (apk|appbundle)\b').hasMatch(l)).toList();
      expect(builds, isNotEmpty, reason: f);
      for (final l in builds) {
        expect(l, contains('--dart-define=$name="\$$name"'), reason: '$f: $l');
      }
    }
    expect(File('.github/workflows/release.yml').readAsStringSync(), contains('$name: \${{ secrets.$name }}'));
    expect(File('.eas/workflows/play-store.yml').readAsStringSync(), contains('if [ -n "\$$name" ]; then echo "$name is set"'),
        reason: 'the EAS log shows whether the Play build saw the variable');
  });

  test('local runs read the id from a file git ignores; the tracked example is empty', () {
    expect(jsonDecode(File('dart_defines.example.json').readAsStringSync()), {name: ''});
    expect(File('.gitignore').readAsLinesSync(), contains('/dart_defines.json'));
  });
}
