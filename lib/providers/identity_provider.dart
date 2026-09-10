import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

/// O matcher de um console. Null quando o console não tem pacote, que é o
/// mesmo contrato do `metadataPackProvider`.
///
/// Existe para memoizar: os três índices custam uma passada por todos os dumps
/// do console, e refazer isso a cada rebuild não tem cabimento.
final packMatcherProvider =
    FutureProvider.family<PackMatcher?, PackTarget>((ref, target) async {
  final pack = await ref.watch(metadataPackProvider(target).future);
  if (pack == null) return null;
  return PackMatcher(pack);
});

/// O eixo local de um console, por cima do mesmo matcher memoizado.
final localIdentityServiceProvider =
    FutureProvider.family<LocalIdentityService?, PackTarget>(
        (ref, target) async {
  final matcher = await ref.watch(packMatcherProvider(target).future);
  if (matcher == null) return null;
  return LocalIdentityService(matcher: matcher);
});
