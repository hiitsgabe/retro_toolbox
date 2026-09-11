import 'package:roms_downloader/models/settings_model.dart';

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
