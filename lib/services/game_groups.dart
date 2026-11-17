import 'package:retro_toolbox/models/game_group_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/disc_sets.dart';

final _extension = RegExp(r'\.[A-Za-z0-9]{1,5}$');
final _tag = RegExp(r'\(([^)]*)\)');
final _discTag = RegExp(r'^(?:Disc|Disk|CD) (\d+)$', caseSensitive: false);
final _revisionTag = RegExp(r'^Rev\b', caseSensitive: false);
final _extraTag = RegExp(
  r'^(?:.*\bDemo\b.*|.*\bPreviews?\b.*|.*\bSampler\b.*|Sample|.*Taikenban.*|.*Otameshi.*|Trial.*|Beta(?: \d+)?|Proto(?:type)?(?: \d+)?|Alpha.*|\d{4}-\d{2}-\d{2}|.*Kiosk.*|Promo)$',
  caseSensitive: false,
);
final _bonusTag = RegExp(r'\b(?:Bonus|Special Disc)\b', caseSensitive: false);
final _boxWord = RegExp(r'\b(?:Collection|Anthology|Trilogy)\b');

String _name(Game g) => g.title.replaceFirst(_extension, '');

/// The No-Intro title: the name before its first " (".
String baseTitleOf(Game g) {
  final n = _name(g);
  final cut = n.indexOf(' (');
  return (cut < 0 ? n : n.substring(0, cut)).trim();
}

/// The name's tags in parentheses, in order.
List<String> tagsOf(Game g) {
  final n = _name(g);
  final cut = n.indexOf(' (');
  if (cut < 0) return const [];
  return [for (final m in _tag.allMatches(n.substring(cut))) m.group(1)!.trim()];
}

/// A demo, preview, sampler, beta or prototype, or a bonus disc that is not
/// a numbered disc of a set.
bool isExtra(Game g) {
  final tags = tagsOf(g);
  if (tags.any(_extraTag.hasMatch)) return true;
  return !tags.any(_discTag.hasMatch) && tags.any(_bonusTag.hasMatch);
}

/// The tags that tell versions apart: all but the disc number and, unless
/// [keepDiscName], the disc's own name (the tag right after the number,
/// when it is not a revision: "(Disc 1) (Ichi)").
List<String> versionTags(Game g, {bool keepDiscName = false}) {
  final tags = tagsOf(g);
  final out = <String>[];
  var nameAt = -1;
  for (var i = 0; i < tags.length; i++) {
    final t = tags[i];
    if (_discTag.hasMatch(t)) {
      nameAt = i + 1;
      continue;
    }
    if (i == nameAt && !keepDiscName && !_revisionTag.hasMatch(t)) continue;
    out.add(t);
  }
  return out;
}

/// What an extra's row says: its tags ("USA · Demo", "USA · Beta · 1998-06-15").
String extraLabel(Game g) => tagsOf(g).join(' · ');

/// A box set game's name without the box's ("Arc the Lad II").
String memberLabel(GameGroup box, GameGroup member) {
  final prefix = '${box.title} - ';
  return member.title.startsWith(prefix) ? member.title.substring(prefix.length) : member.title;
}

/// [games] as games: files with the same base title together; base titles
/// whose prefix before " - " holds `Collection`, `Anthology` or `Trilogy` as one
/// box set; and groups LaunchBox matched to one game joined (box sets excepted). In the
/// order the games first appear.
List<GameGroup> buildGameGroups(List<Game> games) {
  final byBase = <String, List<Game>>{};
  for (final g in games) {
    byBase.putIfAbsent(baseTitleOf(g), () => []).add(g);
  }
  final boxes = <String, List<String>>{};
  for (final base in byBase.keys) {
    final cut = base.indexOf(' - ');
    if (cut <= 0) continue;
    final prefix = base.substring(0, cut);
    if (_boxWord.hasMatch(prefix)) boxes.putIfAbsent(prefix, () => []).add(base);
  }
  final boxOf = <String, String>{
    for (final e in boxes.entries)
      if (e.value.length >= 2)
        for (final base in e.value) base: e.key,
  };
  final keyed = <String, List<String>>{};
  for (final e in byBase.entries) {
    final box = boxOf[e.key];
    final id = box == null ? _launchboxIdOf(e.value) : null;
    final key = box != null ? 'box:$box' : (id != null ? 'launchbox:$id' : 'title:${e.key}');
    keyed.putIfAbsent(key, () => []).add(e.key);
  }
  return [
    for (final e in keyed.entries)
      if (e.key.startsWith('box:'))
        GameGroup(title: e.key.substring(4), members: [for (final base in e.value) _group(byBase[base]!)])
      else
        _group([for (final base in e.value) ...byBase[base]!]),
  ];
}

/// The LaunchBox id most of [files] carry, the smallest on a tie.
int? _launchboxIdOf(List<Game> files) {
  final counts = <int, int>{};
  for (final f in files) {
    final id = f.details?.launchboxId;
    if (id != null) counts[id] = (counts[id] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final ranked = counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  return ranked.first.key;
}

GameGroup _group(List<Game> files) {
  final extras = [for (final f in files) if (isExtra(f)) f];
  final versions = _versions([for (final f in files) if (!isExtra(f)) f]);
  final main = pickMainVersion(versions, defaultRegionOrder);
  return GameGroup(title: baseTitleOf(main?.first ?? extras.first), versions: versions, extras: extras);
}

/// Files with the same base title and version tags are one version. Where
/// that gives a version two discs with one number (or numbered and
/// unnumbered files together), the disc names were edition names: those
/// files are keyed again with them.
List<GameVersion> _versions(List<Game> files) {
  String key(Game f, {bool keepDiscName = false}) => '${baseTitleOf(f)}|${versionTags(f, keepDiscName: keepDiscName).join('|')}';
  final first = <String, List<Game>>{};
  for (final f in files) {
    first.putIfAbsent(key(f), () => []).add(f);
  }
  final sets = <String, List<Game>>{};
  for (final e in first.entries) {
    final clean = _discsConsistent(e.value);
    for (final f in e.value) {
      sets.putIfAbsent(clean ? e.key : key(f, keepDiscName: true), () => []).add(f);
    }
  }
  return [
    for (final discs in sets.values)
      GameVersion(discs: [...discs]..sort((a, b) => discNumber(a).compareTo(discNumber(b))), tags: _commonTags(discs)),
  ];
}

bool _discsConsistent(List<Game> files) {
  final numbers = [for (final f in files) if (discNumber(f) > 0) discNumber(f)];
  return numbers.length == numbers.toSet().length && (numbers.isEmpty || numbers.length == files.length);
}

/// The tags every one of [discs] has, disc names kept, in the first's order.
List<String> _commonTags(List<Game> discs) {
  final all = [for (final d in discs) versionTags(d, keepDiscName: true)];
  return [for (final t in all.first) if (all.every((tags) => tags.contains(t))) t];
}

/// The list's entry for [group] under a filter: the main version (among the
/// versions [passes] lets through, by [regions]) carrying the group; for a
/// group with no version, its first extra that passes; for a box set, its
/// first game's entry with no disc set. Null when nothing passes or [text]
/// matches no title of the group.
Game? groupEntry(GameGroup group, bool Function(Game) passes, {String text = '', List<String> regions = defaultRegionOrder}) {
  if (text.isNotEmpty) {
    final t = text.toLowerCase();
    final hit = group.title.toLowerCase().contains(t) ||
        group.files.any((g) => g.title.toLowerCase().contains(t) || g.displayTitle.toLowerCase().contains(t));
    if (!hit) return null;
  }
  if (group.isBoxSet) {
    for (final m in group.members) {
      final e = groupEntry(m, passes, regions: regions);
      if (e != null) return e.copyWith(group: group, discs: const []);
    }
    return null;
  }
  final main = pickMainVersion([for (final v in group.versions) if (passes(v.first)) v], regions);
  if (main != null) return main.entry.copyWith(group: group);
  if (group.versions.isNotEmpty) return null;
  final extra = group.extras.where(passes).firstOrNull;
  return extra?.copyWith(group: group);
}
