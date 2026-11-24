import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launcher/launch_command.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';

void main() {
  group('splitCommand', () {
    test('spaces separate, quotes keep them, an open quote is null', () {
      expect(splitCommand('  -a  "two words" \'x y\' z'), ['-a', 'two words', 'x y', 'z']);
      expect(splitCommand('-e key ""'), ['-e', 'key', '']);
      expect(splitCommand('-e key "open'), isNull);
    });
  });

  group('parseAndroidCommand', () {
    test('the default command is a VIEW on our provider URI to the named activity', () {
      final r = parseAndroidCommand(defaultAndroidCommand('org.fork', 'org.fork.Main'), package: 'org.fork');
      expect(r.error, isNull);
      final b = r.block!;
      expect(b.packages, ['org.fork']);
      expect((b.activity, b.action), ('org.fork.Main', 'android.intent.action.VIEW'));
      expect((b.rom.mode, b.rom.multiFileMode, b.rom.extra), (RomMode.provider, RomMode.provider, null));
      expect(b.extras, isEmpty);
    });

    test('every option lands where am start puts it', () {
      final r = parseAndroidCommand(
        '-n org.fork/.ui.Emu -a org.fork.LAUNCH -t application/octet-stream -c android.intent.category.DEFAULT -d {rom.uri} '
        '-e rom {rom.uri} --ez fullscreen true --ei slot 2 --el stamp 9000000000 --esa list a,b --activity-clear-task --activity-no-history',
        package: 'org.fork',
      );
      expect(r.error, isNull);
      final b = r.block!;
      expect(b.activity, 'org.fork.ui.Emu');
      expect(b.action, 'org.fork.LAUNCH');
      expect(b.mimeType, 'application/octet-stream');
      expect(b.categories, ['android.intent.category.DEFAULT']);
      expect(b.flags, [LaunchFlag.clearTask, LaunchFlag.noHistory]);
      expect([for (final e in b.extras) '${e.key} ${e.type.name} ${e.value}'], [
        'rom string {rom.uri}',
        'fullscreen bool true',
        'slot int 2',
        'stamp long 9000000000',
        'list stringArray [a, b]',
      ]);
      expect(b.rom.mode, RomMode.provider);
    });

    test('only a path placeholder sends the path in that extra', () {
      final b = parseAndroidCommand('-n org.fork/org.fork.Main -e ROM {rom.path} -e other x', package: 'org.fork').block!;
      expect((b.rom.mode, b.rom.extra), (RomMode.path, 'ROM'));
      final withUri = parseAndroidCommand('-n org.fork/org.fork.Main -d {rom.uri} -e ROM {rom.path}', package: 'org.fork').block!;
      expect(withUri.rom.mode, RomMode.provider, reason: 'the URI is asked for too');
    });

    test('what it refuses, and why', () {
      String? error(String c) => parseAndroidCommand(c, package: 'org.fork').error;
      expect(error('-a android.intent.action.VIEW'), 'Add -n org.fork/<activity>');
      expect(error('-n other.app/.Main'), '-n names other.app, but this emulator is org.fork');
      expect(error('-n org.fork'), '-n takes package/activity');
      expect(error('-n org.fork/.Main -d file:///x'), startsWith('-d takes {rom.uri}'));
      expect(error('-n org.fork/.Main --ez full yes'), '--ez full takes true or false');
      expect(error('-n org.fork/.Main --ei slot two'), '--ei slot takes a whole number');
      expect(error('-n org.fork/.Main -e key'), '-e needs a key and a value');
      expect(error('-n org.fork/.Main -x'), 'Unknown option -x');
      expect(error('-n "org.fork/.Main'), 'A quote is not closed');
    });
  });

  group('parseDesktopCommand', () {
    test('the arguments, as long as one carries the game', () {
      expect(parseDesktopCommand('-fullscreen "{rom}"').args, ['-fullscreen', '{rom}']);
      expect(parseDesktopCommand('-batch').error, 'Put {rom} where the game file goes');
    });
  });

  group('a generic manual emulator', () {
    const viewer = ManualEmulator(variant: 'org.fork', label: 'Fork', recipe: ManualEmulator.generic, systems: ['psx'], activity: 'org.fork.Main');

    test('opens the way its edited command says, on Android and desktop', () {
      final android = presetsWithManual(const [], [viewer.withCommand('-n org.fork/.Play -a org.fork.GO -e path {rom.path}')], os: 'android').single.android!;
      expect((android.activity, android.action, android.rom.mode, android.rom.extra), ('org.fork.Play', 'org.fork.GO', RomMode.path, 'path'));
      const exe = ManualEmulator(variant: '/opt/fork/fork', label: 'fork', recipe: ManualEmulator.generic, systems: ['psx'], command: '--fullscreen {rom}');
      expect(presetsWithManual(const [], [exe], os: 'linux').single.linux!.args, ['--fullscreen', '{rom}']);
    });

    test('a command that does not read falls back to the default', () {
      final android = presetsWithManual(const [], [viewer.withCommand('-x')], os: 'android').single.android!;
      expect((android.activity, android.action), ('org.fork.Main', 'android.intent.action.VIEW'));
    });

    test('the command round-trips through JSON, and commandFor shows the default when none is saved', () {
      final edited = viewer.withCommand('-n org.fork/.Play');
      expect(ManualEmulator.fromJson(edited.toJson())!.command, '-n org.fork/.Play');
      expect(viewer.commandFor('android'), '-n org.fork/org.fork.Main -a android.intent.action.VIEW -d {rom.uri}');
      expect(viewer.commandFor('linux'), '{rom}');
    });
  });
}
