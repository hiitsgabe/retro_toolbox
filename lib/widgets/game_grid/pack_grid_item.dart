import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// O tile de MODO PACK: representa um **jogo**, não um arquivo.
///
/// Widget puro de propósito. Ele não sabe o que é `PackGridEntry`, não lê
/// provider nenhum e não decide nada: quem monta é `PackGrid` (Task 12).
///
/// O que ele **não** tem, e a ausência é a parte importante:
/// - nenhum parâmetro de confiança de match. O tile mostra disponibilidade,
///   e um jogo com uma fonte confirmada e uma no chute é um jogo só. Ver
///   "Armadilha de leitura" no plano da fatia 3.
/// - nenhum botão de baixar. O tile não sabe qual arquivo baixar, então não
///   pode ter botão de baixar (spec de UI, seção 3.1).
/// - nenhuma tag de região, revisão ou disco. Essas descrevem uma versão.
class PackGridItem extends StatelessWidget {
  final String title;

  /// URL da capa do pacote. Nulo cai no marcador de capa ausente.
  final String? coverUrl;

  /// Se algum addon tem algum arquivo para este jogo. **É o único eixo que
  /// muda o desenho do tile.**
  final bool hasSource;

  /// Se alguma versão deste jogo já está no disco (Task 13). Enquanto o scan
  /// não terminou vem `false`, porque borda errada é pior que borda ausente.
  final bool isOwned;

  final bool isSelected;

  /// Se há seleção em curso. Com seleção vazia o checkbox some de **todos**
  /// os tiles, para a capa ficar limpa (spec de UI, seção 4).
  final bool selectionActive;

  final double aspectRatio;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelection;

  const PackGridItem({
    super.key,
    required this.title,
    required this.hasSource,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelection,
    this.coverUrl,
    this.isOwned = false,
    this.isSelected = false,
    this.selectionActive = false,
    this.aspectRatio = 0.75,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color? borderColor = isSelected
        ? scheme.primary
        : isOwned
            ? scheme.secondaryContainer
            : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        key: const ValueKey('pack-tile-border'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: borderColor ?? Theme.of(context).dividerColor.withValues(alpha: 0.2),
            width: borderColor != null ? 3 : 1,
          ),
        ),
        child: Tooltip(
          message: title,
          // Sem `manual` o `Tooltip` monta um `LongPressGestureRecognizer`
          // próprio, porque `TooltipTriggerMode.longPress` é o padrão em
          // mobile e o `flutter_test` roda como Android. Esse reconhecedor é
          // o mais interno, ganha a arena e engole o toque longo do
          // `GestureDetector` de fora, então a seleção nunca dispara.
          // `manual` tira só o gatilho de toque e mantém o hover de desktop,
          // que é onde a dica de título truncado serve para alguma coisa. Em
          // mobile o toque longo é da seleção, e isso é decisão travada.
          triggerMode: TooltipTriggerMode.manual,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _cover(context),
                ),
                if (selectionActive)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggleSelection(),
                        shape: const CircleBorder(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                // Dois sinais redundantes para "sem fonte": a capa dessaturada
                // e este ícone. Cinza sozinho confunde com "carregando", e
                // muita capa de época já é quase monocromática.
                if (!hasSource)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                      shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 1)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final url = coverUrl;
    final capa = url == null
        ? _placeholder(context)
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (context, _, __) => _placeholder(context),
            errorListener: (_) {},
          );
    if (hasSource) return capa;
    // Matriz de saturação zero. É o mesmo truque do `ColorFilter.mode` com
    // cinza, mas preserva o brilho da arte em vez de achatá-la.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: capa,
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.3),
            scheme.secondaryContainer.withValues(alpha: 0.2),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.videogame_asset_rounded,
          size: 32,
          color: scheme.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
