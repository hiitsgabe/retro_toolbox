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

  test('the maintainer doc and the build files carry no client id and no secret', () {
    final clientId = RegExp(r'[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com');
    for (final f in ['docs/google-cloud.md', 'dart_defines.example.json', '.github/workflows/release.yml', '.eas/workflows/play-store.yml', 'README.md']) {
      final text = File(f).readAsStringSync();
      expect(clientId.hasMatch(text), isFalse, reason: f);
      expect(text, isNot(contains('GOCSPX-')), reason: '$f: a client secret');
    }
  });

  test('the privacy policy says what Save Sync does with Google Drive', () {
    final policy = File('website/privacy.html').readAsStringSync();
    for (final words in ['Save Sync with Google Drive', 'Retro Toolbox Saves', 'drive.file', 'Limited Use', 'No save, sign-in token or account detail reaches the developer']) {
      expect(policy, contains(words));
    }
    expect(policy, isNot(contains('Retro Toolbox has no accounts,')), reason: 'Google sign-in is an account');
  });
}
