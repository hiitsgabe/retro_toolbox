import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

/// The matcher for a console. Null when the console has no pack. Memoized:
/// the three indexes cost one pass over every dump of the console.
final packMatcherProvider =
    FutureProvider.family<PackMatcher?, PackTarget>((ref, target) async {
  final pack = await ref.watch(metadataPackProvider(target).future);
  if (pack == null) return null;
  return PackMatcher(pack);
});

/// A console's local identity axis, over the same memoized matcher.
final localIdentityServiceProvider =
    FutureProvider.family<LocalIdentityService?, PackTarget>(
        (ref, target) async {
  final matcher = await ref.watch(packMatcherProvider(target).future);
  if (matcher == null) return null;
  return LocalIdentityService(matcher: matcher);
});
