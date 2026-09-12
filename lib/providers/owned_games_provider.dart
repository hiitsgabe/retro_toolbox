import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Onde a biblioteca do console selecionado está no disco.
///
/// Existe separado do provider de baixo por um motivo só: é o ponto de
/// injeção do teste. `getDownloadDir` mora no notifier de settings, e o
/// construtor de `SettingsNotifier` lê o disco; sobrescrever este provider é o
/// que permite varrer uma pasta temporária sem subir settings de verdade.
final libraryDirProvider = Provider<String?>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return null;
  // O `watch` é do estado e a chamada é no notifier. É esse par que faz este
  // provider recalcular quando o usuário troca a pasta nas configurações.
  ref.watch(settingsProvider);
  final dir = ref.read(settingsProvider.notifier).getDownloadDir(target.consoleId);
  return dir.isEmpty ? null : dir;
});

/// Os `PackGame.id` que já têm alguma versão no disco.
///
/// Uma varredura por console, nunca uma por tile: `identify` pode calcular
/// CRC, e chamá-la de dentro de um `itemBuilder` seria chamá-la de novo a
/// cada quadro de scroll. O tile recebe o conjunto pronto e faz `contains`.
final ownedGameIdsProvider = FutureProvider<Set<String>>((ref) async {
  final target = ref.watch(packTargetProvider);
  final dir = ref.watch(libraryDirProvider);
  if (target == null || dir == null) return const <String>{};

  final identity = await ref.watch(localIdentityServiceProvider(target).future);
  if (identity == null) return const <String>{};

  final owned = <String>{};
  for (final file in await _libraryFiles(dir)) {
    if (!hasRomExtension(p.basename(file.path))) continue;
    final match = await identity.identify(file);
    // `guess` é o tier de similaridade, e ele erra. Borda errada é pior que
    // borda ausente (spec de UI, seção 3.1), então só nome exato, título
    // canônico e CRC pintam.
    if (match == null || match.confidence == MatchConfidence.guess) continue;
    owned.add(match.game.id);
  }
  return owned;
});

/// Os arquivos da pasta e de um nível abaixo dela.
///
/// O nível a mais não é capricho: com `extractToFolder` ligado a ROM extraída
/// fica em `<pasta>/<nome do jogo>/`, e `_scanLibraryDirIsolate`
/// (`lib/providers/library_snapshot_provider.dart:273-294`) já conta essa
/// profundidade. Varrer diferente daria duas respostas para "eu já baixei
/// isso?" dentro da mesma tela.
Future<List<File>> _libraryFiles(String dir) async {
  final root = Directory(dir);
  if (!await root.exists()) return const [];

  final files = <File>[];
  try {
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        try {
          await for (final sub in entity.list(followLinks: false)) {
            if (sub is File) files.add(sub);
          }
        } catch (_) {
          // Subpasta sem permissão. Não é motivo para a grade inteira ficar
          // sem borda.
        }
      }
    }
  } catch (_) {
    // Pasta apagada no meio da varredura, pendrive removido, permissão
    // negada. Devolve o que deu para ler.
  }
  return files;
}
