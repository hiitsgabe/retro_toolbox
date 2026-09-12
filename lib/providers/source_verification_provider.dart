import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/source_verification_service.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// O que identifica uma verificação.
///
/// É record, e não classe, porque record tem igualdade estrutural de graça, e
/// é essa igualdade que faz a família do Riverpod cachear. Com uma classe sem
/// `operator ==`, cada rebuild criaria uma chave nova e a verificação rodaria
/// de novo a cada frame, com duas requisições por vez.
///
/// A chave efetiva é (fonte, arquivo), como pede a seção 8 do spec de UI. Os
/// outros dois campos são função desses dois e estão aqui só para o provider
/// não precisar receber a fonte inteira.
typedef SourceVerificationRequest = ({
  String sourceId,
  String filename,
  String? url,
  String gameId,
});

/// O verificador do console atual. Null quando o console não tem pacote, que é
/// o mesmo contrato de `packMatcherProvider`.
///
/// Fica separado do provider de veredito porque é ele que carrega o `fetch` de
/// produção, e é ele que o teste sobrescreve para não ir à rede.
final sourceVerificationServiceProvider =
    FutureProvider.family<SourceVerificationService?, PackTarget>((ref, target) async {
  final matcher = await ref.watch(packMatcherProvider(target).future);
  if (matcher == null) return null;
  return SourceVerificationService(
    matcher: matcher,
    fetch: ZipCentralDirectory.httpRangeFetch,
  );
});

/// O veredito de CRC de uma fonte.
///
/// **Não é `autoDispose`, de propósito.** A família viva é o cache que a seção
/// 8 pede quando diz que a segunda abertura do mesmo jogo é instantânea. O que
/// fica na memória é um enum por (fonte, arquivo) visto, não os bytes.
///
/// Nunca devolve [SourceVerification.verifying]: enquanto a leitura roda, quem
/// está em `verifying` é o próprio `AsyncValue`. Traduza com [verificationOf].
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

/// O estado que a tela pinta, a partir do que o provider devolveu.
///
/// Erro vira `impossible` e não tela vermelha: `verify` não levanta, então
/// chegar aqui significa que o pacote do console não carregou, e nesse caso o
/// que o usuário precisa saber é que não deu para verificar.
SourceVerification verificationOf(AsyncValue<SourceVerification> value) => value.when(
      data: (veredito) => veredito,
      loading: () => SourceVerification.verifying,
      error: (_, __) => SourceVerification.impossible,
    );
