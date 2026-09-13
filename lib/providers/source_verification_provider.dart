import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/source_verification_service.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// What identifies a verification. A record so its structural equality lets
/// the Riverpod family cache. The effective key is (source, file).
typedef SourceVerificationRequest = ({
  String sourceId,
  String filename,
  String? url,
  String gameId,
});

/// The current console's verifier. Null when the console has no pack. Carries
/// the production `fetch`; tests override it to stay off the network.
final sourceVerificationServiceProvider =
    FutureProvider.family<SourceVerificationService?, PackTarget>((ref, target) async {
  final matcher = await ref.watch(packMatcherProvider(target).future);
  if (matcher == null) return null;
  return SourceVerificationService(
    matcher: matcher,
    fetch: ZipCentralDirectory.httpRangeFetch,
  );
});

/// The CRC verdict for a source. Not `autoDispose`: the live family is the
/// cache, one enum per (source, file) seen, not the bytes.
///
/// Never returns [SourceVerification.verifying]; while the read runs the
/// `AsyncValue` is loading. Translate with [verificationOf].
final sourceVerificationProvider =
    FutureProvider.family<SourceVerification, SourceVerificationRequest>((ref, request) async {
  final target = ref.watch(packTargetProvider);
  if (target == null) return SourceVerification.notVerified;

  final url = request.url;
  if (url == null) return SourceVerification.impossible;
  final uri = Uri.tryParse(url);
  if (uri == null) return SourceVerification.impossible;

  final service = await ref.watch(sourceVerificationServiceProvider(target).future);
  if (service == null) return SourceVerification.notVerified;

  return service.verify(uri, request.filename, request.gameId);
});

/// The state the screen paints from what the provider returned. Error becomes
/// `impossible`, not a red screen: it means the console's pack failed to load.
SourceVerification verificationOf(AsyncValue<SourceVerification> value) => value.when(
      data: (verdict) => verdict,
      loading: () => SourceVerification.verifying,
      error: (_, __) => SourceVerification.impossible,
    );
