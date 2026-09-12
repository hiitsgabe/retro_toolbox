import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

/// Se o app tem token para este console.
///
/// Serve para a UI decidir se mostra o console como conectado. Lê **só** as
/// settings, que desde a Task 6 vêm do cofre.
///
/// Existe como função em vez de expressão inline porque a expressão estava
/// copiada em duas telas, e foi essa duplicação que fez a seção 6.3 do spec
/// contar dois sítios quando são quatro: um `grep` por
/// `buildConsoleAuthHeaders` não acha nenhuma das duas.
bool consoleHasToken(AppSettings settings, String consoleId) => settings.consoleSettings[consoleId]?.authToken?.isNotEmpty ?? false;

/// Os addons que serviram [games] e cuja fonte neste console pede token.
///
/// Pura e aqui, e não dentro de `TaskQueueService._downloadBlockReason`,
/// porque aquele método é estático, assíncrono e cheio de `ref`: sem separar,
/// a regra de bloqueio só teria teste através de widget.
///
/// Dois casos que a lista deixa de fora de propósito. Um jogo cujo `sourceId`
/// não está mais entre as fontes do console (cache de addon removido) não
/// bloqueia nada, porque não haveria onde o usuário digitar a conta que
/// faltou. E um addon aberto no mesmo console que um privado não é contagiado
/// pela conta do vizinho: baixar do aberto não precisa dela.
List<String> addonsThatNeedToken(List<Game> games, List<ConsoleSource> sources) {
  final pedem = <String>{};
  final vistos = <String>{};
  for (final fonte in sources) {
    // Primeira fonte de cada addon manda, igual a `authForAddon` e a
    // `MergedCatalog.coverage`. Sem isto, um addon com um espelho sem auth e
    // outro com auth responderia uma coisa aqui e outra na tela.
    if (!vistos.add(fonte.addonId)) continue;
    if (authNeedsToken(fonte.auth)) pedem.add(fonte.addonId);
  }

  return [
    for (final addonId in {for (final game in games) game.sourceId})
      if (pedem.contains(addonId)) addonId,
  ];
}
