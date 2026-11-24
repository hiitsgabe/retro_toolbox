/// The launch command of an emulator added with "Just open the file", which
/// the user can edit. On Android it reads like the arguments of `am start`
/// (the form Daijishou and Beacon use); on desktop it is the arguments after
/// the executable. Pure Dart, like launch_preset.dart.
library;

import 'package:retro_toolbox/services/launcher/launch_preset.dart';

/// What an Android command starts with when nothing was edited.
String defaultAndroidCommand(String package, String activity) => '-n $package/$activity -a android.intent.action.VIEW -d {rom.uri}';

/// What a desktop command starts with when nothing was edited.
const defaultDesktopCommand = '{rom}';

/// The placeholders a command may use.
const commandPlaceholders = ['{rom}', '{rom.path}', '{rom.uri}'];

/// [command] split as a shell would: spaces separate, and "double" or
/// 'single' quotes keep spaces. Null for a quote left open.
List<String>? splitCommand(String command) {
  final out = <String>[];
  final word = StringBuffer();
  var inWord = false;
  String? quote;
  for (final ch in command.split('')) {
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        word.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      inWord = true;
    } else if (ch.trim().isEmpty) {
      if (inWord) out.add(word.toString());
      word.clear();
      inWord = false;
    } else {
      word.write(ch);
      inWord = true;
    }
  }
  if (quote != null) return null;
  if (inWord) out.add(word.toString());
  return out;
}

/// The Android block [command] describes for [package], or why it cannot be
/// one. The file always goes to the app through Retro Toolbox's own
/// provider, with a read grant, in the intent data, unless only
/// `{rom.path}` is used: then it goes as a path in that extra, which needs
/// an app that can read your storage.
({AndroidBlock? block, String? error}) parseAndroidCommand(String command, {required String package}) {
  final words = splitCommand(command);
  if (words == null) return (block: null, error: 'A quote is not closed');
  String? activity, mime;
  var action = 'android.intent.action.VIEW';
  var data = false;
  final categories = <String>[];
  final flags = <LaunchFlag>[];
  final extras = <PresetExtra>[];
  String? fail;
  var i = 0;
  String? next(String option) {
    if (i + 1 >= words.length) {
      fail = '$option needs a value';
      return null;
    }
    return words[++i];
  }

  ({String key, String value})? pair(String option) {
    if (i + 2 >= words.length) {
      fail = '$option needs a key and a value';
      return null;
    }
    final key = words[++i];
    return (key: key, value: words[++i]);
  }

  for (; i < words.length && fail == null; i++) {
    final w = words[i];
    switch (w) {
      case '-n':
        final v = next(w);
        if (v == null) break;
        final slash = v.indexOf('/');
        if (slash < 0) {
          fail = '-n takes package/activity';
          break;
        }
        final pkg = v.substring(0, slash), act = v.substring(slash + 1);
        if (pkg != package) {
          fail = '-n names $pkg, but this emulator is $package';
          break;
        }
        if (act.isEmpty) {
          fail = '-n takes package/activity';
          break;
        }
        activity = act.startsWith('.') ? '$pkg$act' : act;
      case '-a':
        final v = next(w);
        if (v != null) action = v;
      case '-d':
        final v = next(w);
        if (v == null) break;
        if (v != '{rom.uri}' && v != '{rom}') {
          fail = '-d takes {rom.uri}: the file always reaches the app through Retro Toolbox';
          break;
        }
        data = true;
      case '-t':
        final v = next(w);
        if (v != null) mime = v;
      case '-c':
        final v = next(w);
        if (v != null) categories.add(v);
      case '-e' || '--es':
        final e = pair(w);
        if (e != null) extras.add(PresetExtra(key: e.key, type: ExtraType.string, value: e.value));
      case '--ez':
        final e = pair(w);
        if (e == null) break;
        if (e.value != 'true' && e.value != 'false') {
          fail = '--ez ${e.key} takes true or false';
          break;
        }
        extras.add(PresetExtra(key: e.key, type: ExtraType.bool, value: e.value == 'true'));
      case '--ei' || '--el':
        final e = pair(w);
        if (e == null) break;
        final n = int.tryParse(e.value);
        if (n == null) {
          fail = '$w ${e.key} takes a whole number';
          break;
        }
        extras.add(PresetExtra(key: e.key, type: w == '--ei' ? ExtraType.int : ExtraType.long, value: n));
      case '--esa':
        final e = pair(w);
        if (e != null) extras.add(PresetExtra(key: e.key, type: ExtraType.stringArray, value: e.value.split(',')));
      case '--activity-clear-task':
        flags.add(LaunchFlag.clearTask);
      case '--activity-clear-top':
        flags.add(LaunchFlag.clearTop);
      case '--activity-no-history':
        flags.add(LaunchFlag.noHistory);
      default:
        fail = 'Unknown option $w';
    }
  }
  if (fail != null) return (block: null, error: fail);
  if (activity == null) return (block: null, error: 'Add -n $package/<activity>');
  bool uses(String placeholder) => extras.any((e) => e.templates.any((t) => t.contains(placeholder)));
  // A path only when nothing asks for the URI: the provider URI rides the
  // data whatever the command says, and a path extra beside it would be read
  // by an app that cannot open it.
  final pathExtra = !data && !uses('{rom.uri}') && !uses('{rom}')
      ? extras.where((e) => e.type == ExtraType.string && e.templates.any((t) => t.contains('{rom.path}'))).firstOrNull?.key
      : null;
  return (
    block: AndroidBlock(
      packages: [package],
      activity: activity,
      action: action,
      categories: categories,
      mimeType: mime,
      flags: flags,
      rom: pathExtra != null
          ? RomSpec(mode: RomMode.path, multiFileMode: RomMode.path, extra: pathExtra)
          : const RomSpec(mode: RomMode.provider, multiFileMode: RomMode.provider),
      extras: extras,
    ),
    error: null,
  );
}

/// The arguments [command] gives the executable, or why it cannot.
({List<String>? args, String? error}) parseDesktopCommand(String command) {
  final words = splitCommand(command);
  if (words == null) return (args: null, error: 'A quote is not closed');
  if (!words.any((w) => commandPlaceholders.any(w.contains))) return (args: null, error: 'Put {rom} where the game file goes');
  return (args: words, error: null);
}
