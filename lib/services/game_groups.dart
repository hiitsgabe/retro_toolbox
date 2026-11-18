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

/// The name's trailing run of tags: "Euro Demo (Future) 94 (Europe)" has only
/// "(Europe)". Tags before plain words belong to the title.
final _trailingTags = RegExp(r'^(.*?)((?: \([^)]*\))+)$');

/// The No-Intro title: the name minus its trailing run of tags.
String baseTitleOf(Game g) => _parse(g).$1;

/// The name's trailing tags in parentheses, in order.
List<String> tagsOf(Game g) => _parse(g).$2;

// Reading a name is most of what building the groups costs and each title is
// read several times, so it is read once. Per isolate; cleared when it grows
// past any catalog.
final _parsed = <String, (String, List<String>)>{};

(String, List<String>) _parse(Game g) {
  final hit = _parsed[g.title];
  if (hit != null) return hit;
  if (_parsed.length > 100000) _parsed.clear();
  final n = _name(g);
  final m = _trailingTags.firstMatch(n);
  return _parsed[g.title] = (
    (m == null ? n : m.group(1)!).trim(),
    m == null ? const <String>[] : List.unmodifiable([for (final t in _tag.allMatches(m.group(2)!)) t.group(1)!.trim()]),
  );
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
/// when it is not a revision and not one of [editions]: "(Disc 1) (Ichi)").
List<String> versionTags(Game g, {bool keepDiscName = false, Set<String> editions = const {}}) {
  final tags = tagsOf(g);
  final out = <String>[];
  var nameAt = -1;
  for (var i = 0; i < tags.length; i++) {
    final t = tags[i];
    if (_discTag.hasMatch(t)) {
      nameAt = i + 1;
      continue;
    }
    if (i == nameAt && !keepDiscName && !_revisionTag.hasMatch(t) && !editions.contains(t)) continue;
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

/// The tags in name position (right after "Disc N") that are editions, not
/// disc names. In [group] (one first-pass version) an edition follows two
/// different disc numbers; or, anywhere in [base] (every file of the title),
/// it also sits on a numbered file outside the name position.
Set<String> _editionsOf(List<Game> group, List<Game> base) {
  final after = <String, Set<int>>{};
  for (final f in group) {
    final tags = tagsOf(f);
    final n = discNumber(f);
    if (n == 0) continue;
    for (var i = 1; i < tags.length; i++) {
      if (_discTag.hasMatch(tags[i - 1])) (after[tags[i]] ??= {}).add(n);
    }
  }
  final elsewhere = <String>{};
  for (final f in base) {
    if (discNumber(f) == 0) continue;
    final tags = tagsOf(f);
    for (var i = 0; i < tags.length; i++) {
      if (i == 0 || !_discTag.hasMatch(tags[i - 1])) elsewhere.add(tags[i]);
    }
  }
  return {
    for (final e in after.entries)
      if (e.value.length > 1 || elsewhere.contains(e.key)) e.key,
  };
}

/// Files with the same base title and version tags are one version, in
/// passes:
/// 1. key on the tags without disc names;
/// 2. key again with the edition tags of each first-pass group kept;
/// 3. an unnumbered file in a key with other files is a version of its own;
/// 4. where a version still has two discs with one number, the disc names
///    were edition names: those files are keyed again with them.
List<GameVersion> _versions(List<Game> files) {
  final byBase = <String, List<Game>>{};
  for (final f in files) {
    byBase.putIfAbsent(baseTitleOf(f), () => []).add(f);
  }
  String key(Game f, {bool keepDiscName = false, Set<String> editions = const {}}) =>
      '${baseTitleOf(f)}|${versionTags(f, keepDiscName: keepDiscName, editions: editions).join('|')}';
  final first = <String, List<Game>>{};
  for (final f in files) {
    first.putIfAbsent(key(f), () => []).add(f);
  }
  final second = <String, List<Game>>{};
  for (final g in first.values) {
    final editions = _editionsOf(g, byBase[baseTitleOf(g.first)]!);
    for (final f in g) {
      second.putIfAbsent(key(f, editions: editions), () => []).add(f);
    }
  }
  final third = <String, List<Game>>{};
  for (final e in second.entries) {
    final mixed = e.value.length > 1 && e.value.any((f) => discNumber(f) == 0);
    for (final f in e.value) {
      third.putIfAbsent(mixed && discNumber(f) == 0 ? 'file:${f.title}' : e.key, () => []).add(f);
    }
  }
  final sets = <String, List<Game>>{};
  for (final e in third.entries) {
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
/// versions [passes] lets through, the owned one first ([owned]: a file the
/// user has), then by [regions]) carrying the group; for a
/// group with no version, its first extra that passes; for a box set, its
/// first game's entry with no disc set. Null when nothing passes or [text]
/// matches no title of the group.
Game? groupEntry(GameGroup group, bool Function(Game) passes, {String text = '', List<String> regions = defaultRegionOrder, bool Function(Game)? owned}) {
  if (text.isNotEmpty) {
    final t = text.toLowerCase();
    final hit = group.title.toLowerCase().contains(t) ||
        group.files.any((g) => g.title.toLowerCase().contains(t) || g.displayTitle.toLowerCase().contains(t));
    if (!hit) return null;
  }
  if (group.isBoxSet) {
    for (final m in group.members) {
      final e = groupEntry(m, passes, regions: regions, owned: owned);
      if (e != null) return e.copyWith(group: group, discs: const []);
    }
    return null;
  }
  final main = pickMainVersion([for (final v in group.versions) if (passes(v.first)) v], regions, owned: owned == null ? null : (v) => v.discs.any(owned));
  if (main != null) return main.entry.copyWith(group: group);
  if (group.versions.isNotEmpty) return null;
  final extra = group.extras.where(passes).firstOrNull;
  return extra?.copyWith(group: group);
}
