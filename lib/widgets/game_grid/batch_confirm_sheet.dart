import 'package:flutter/material.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// A folha de confirmação da seção 6 do spec de UI.
///
/// Widget puro: recebe o plano e dois callbacks. Quem abre em
/// `showModalBottomSheet` e quem enfileira é o chamador.
class BatchConfirmSheet extends StatelessWidget {
  final BatchPlan plan;
  final ValueChanged<BatchPlan> onConfirm;

  /// Recebe o `gameId` da linha a tirar do lote. O chamador é quem guarda o
  /// plano corrente e aplica `plan.withoutPick`.
  final ValueChanged<String> onRemove;

  const BatchConfirmSheet({
    super.key,
    required this.plan,
    required this.onConfirm,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = plan.picks.length;
    final cabecalho = '$n ${n == 1 ? 'jogo' : 'jogos'}, ${formatBytes(plan.totalBytes)}';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cabecalho,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (plan.uncertainCount > 0)
                  Text(
                    '${plan.uncertainCount} incerto${plan.uncertainCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final pick in plan.picks)
                  ListTile(
                    dense: true,
                    // O selo de incerteza da seção 6. Ele mora AQUI e não no
                    // tile da grade: ver "Armadilha de leitura" no topo.
                    leading: pick.uncertain ? const Icon(Icons.help_outline, size: 20) : null,
                    title: Text(pick.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(pick.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      key: ValueKey('remove-${pick.gameId}'),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Tirar do lote',
                      onPressed: () => onRemove(pick.gameId),
                    ),
                  ),
                if (plan.failures.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Não vão para a fila',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final falha in plan.failures)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.cloud_off_rounded, size: 20, color: scheme.onSurfaceVariant),
                      title: Text(falha.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(falha.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancelar'),
                ),
                const Spacer(),
                FilledButton(
                  // Sem nada escolhido não há o que enfileirar, mas a folha
                  // continua aberta para mostrar os motivos das falhas.
                  onPressed: plan.picks.isEmpty ? null : () => onConfirm(plan),
                  child: const Text('Baixar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
