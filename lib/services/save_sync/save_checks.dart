import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';

/// Inflates gzip or zlib data (some Stardew builds may compress saves); other bytes pass through.
List<int> _inflated(List<int> b) {
  try {
    if (b.length > 2 && b[0] == 0x1f && b[1] == 0x8b) return GZipDecoder().decodeBytes(b);
    if (b.length > 2 && b[0] == 0x78 && (b[0] * 256 + b[1]) % 31 == 0) return ZLibDecoder().decodeBytes(b);
  } catch (_) {}
  return b;
}

bool xmlEndsWith(List<int> bytes, String suffix) => utf8.decode(_inflated(bytes), allowMalformed: true).trimRight().endsWith(suffix);

const _bfHeader = [0x00, 0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];

/// A .NET BinaryFormatter stream: the SerializationHeaderRecord, then records, then MessageEnd (0x0B).
bool binaryFormatterEnvelope(List<int> b) => b.length > _bfHeader.length && listEquals(b.sublist(0, _bfHeader.length), _bfHeader) && b.last == 0x0B;

/// Null when [bytes] pass [check], otherwise why not.
String? failedCheck(SaveCheck check, List<int> bytes) {
  final end = check.xmlEndsWith;
  if (end != null && !xmlEndsWith(bytes, end)) return '${check.file} does not end with $end';
  if (check.binaryFormatterEnvelope && !binaryFormatterEnvelope(bytes)) return '${check.file} is not a complete BinaryFormatter file';
  return null;
}

/// The first string a .NET BinaryWriter wrote: a 7-bit encoded byte length, then UTF-8. Null when malformed.
String? readDotnetString(List<int> b) {
  var length = 0, shift = 0, i = 0;
  while (true) {
    if (i >= b.length || shift > 28) return null;
    final byte = b[i++];
    length |= (byte & 0x7F) << shift;
    if (byte & 0x80 == 0) break;
    shift += 7;
  }
  if (i + length > b.length) return null;
  try {
    return utf8.decode(b.sublist(i, i + length));
  } on FormatException {
    return null;
  }
}

/// Text of the first `<tag>...</tag>`, or null.
String? xmlTagText(List<int> bytes, String tag) {
  final text = utf8.decode(_inflated(bytes), allowMalformed: true);
  return RegExp('<$tag>([^<]*)</$tag>').firstMatch(text)?.group(1)?.trim();
}

/// Compares dotted versions part by part as numbers (missing or non-numeric parts count as 0), up to [parts] parts.
int compareVersions(String a, String b, {int? parts}) {
  List<int> nums(String v) => v.split('.').map((s) => int.tryParse(RegExp(r'^\d+').stringMatch(s) ?? '') ?? 0).toList();
  final x = nums(a), y = nums(b);
  final n = parts ?? (x.length > y.length ? x.length : y.length);
  for (var i = 0; i < n; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Whether a save written by [saveVersion] may go into a game at [installed].
bool versionAllows(VersionRule rule, {required String saveVersion, required String installed, int? parts}) => switch (rule) {
      VersionRule.receiverAtLeastSave => compareVersions(installed, saveVersion, parts: parts) >= 0,
      VersionRule.sameBuild => installed.trim() == saveVersion.trim(),
    };

/// Why [gen] may not go into the game at [installed], or null when it may.
/// Fails closed: a gen that does not record the version the rule needs, or an
/// installed version that cannot be read, is refused.
String? versionRefusal(Recipe r, GenMeta gen, String? installed) {
  final v = r.version;
  if (v == null) return null;
  final saveVersion = v.fromPackage ? gen.packageVersion : gen.gameVersion;
  if (saveVersion == null) return '${gen.gen} does not record its version';
  if (installed == null) return 'Cannot read the installed version of ${r.name}';
  if (versionAllows(v.rule, saveVersion: saveVersion, installed: installed, parts: v.parts)) return null;
  return v.rule == VersionRule.sameBuild
      ? 'This save is from ${r.name} $saveVersion and the installed one is $installed; install the same version first'
      : 'This save needs ${r.name} $saveVersion or newer; the installed one is $installed';
}
