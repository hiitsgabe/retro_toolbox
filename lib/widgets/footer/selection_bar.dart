import 'package:flutter/material.dart';

/// A faixa de seleção da seção 5 do spec de UI.
///
/// Senta acima do `Footer`, como irmã dele no Column do HomeScreen, nunca
/// dentro dele: as duas ficam ativas ao mesmo tempo e nenhuma esconde a outra.
///
/// Widget puro de propósito: recebe número e callbacks e não conhece Riverpod.
/// Quem liga no provider é o HomeScreen (Task 3).
class SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDownload;

  const SelectionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    // Some sozinha quando zera. SizedBox.shrink e não Visibility, porque a
    // barra não deve reservar altura nenhuma com seleção vazia.
    if (count == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              color: scheme.onPrimary,
              tooltip: 'Limpar seleção',
              onPressed: onClear,
            ),
            Expanded(
              child: Text(
                count == 1 ? '1 selecionado' : '$count selecionados',
                // Mesma política do `footer.dart:99-100`, e pelo mesmo motivo:
                // a faixa tem altura fixa, então com `textScaler` grande em
                // tela estreita o parágrafo pede mais altura do que recebe e
                // é cortado no meio da palavra, sem reticência e sem a faixa
                // amarela de overflow. Medido em 320dp e 360dp com escala 2.0.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: onDownload,
                child: const Text('Baixar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
