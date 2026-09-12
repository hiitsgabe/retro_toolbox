import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/console_merge.dart';

/// A lista ordenada de fontes, como a seção 9 do spec de UI pede.
///
/// A ordem **é** a prioridade: ela alimenta `sourcePriorityProvider`, que
/// alimenta o `sourcePriority` de `planFromEntries`. Arrastar uma linha aqui
/// muda qual fonte baixa o arquivo.
class AddonsScreen extends ConsumerWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonProvider);
    final cobertura = ref.watch(addonCoverageProvider).valueOrNull ?? const <String, AddonCoverage>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Addons')),
      body: Column(
        children: [
          Expanded(
            child: addons.isEmpty
                ? const Center(child: Text('Nenhum addon instalado.'))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: addons.length,
                    onReorder: (from, to) => ref.read(addonProvider.notifier).reorder(from, to),
                    itemBuilder: (context, i) {
                      final addon = addons[i];
                      return _Linha(
                        key: ValueKey(addon.id),
                        indice: i,
                        addon: addon,
                        // Ausente é cobertura zero, não erro: é o estado de um
                        // addon recém instalado cujo catálogo ainda não foi lido.
                        cobertura: cobertura[addon.id] ?? (consoles: const <String>[], authConsoles: const <String>[]),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _dialogoDeInstalacao(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Instalar de URL'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogoDeInstalacao(BuildContext context, WidgetRef ref) async {
    final url = await showDialog<String>(context: context, builder: (_) => const _DialogoDeUrl());
    if (url == null || url.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final vault = (await ref.read(vaultProvider.future)).vault;
      await installAddonFromUrl(
        url,
        notifier: ref.read(addonProvider.notifier),
        vault: vault,
        fetch: ref.read(catalogFetcherProvider),
      );
    } catch (e) {
      // Mensagem em vez de stack trace: os dois erros prováveis são url errada
      // e servidor que devolve página de login, e nenhum dos dois é bug.
      messenger.showSnackBar(SnackBar(content: Text('Não deu para instalar: $e')));
    }
  }
}

/// O diálogo do "Instalar de URL". Tem estado só por causa do `dispose`.
///
/// O `TextEditingController` precisa viver enquanto o `TextField` viver, e o
/// `showDialog` devolve assim que a rota é desempilhada, com a animação de
/// saída ainda rodando. Descartar o controller ali é descartá-lo num quadro em
/// que o `TextField` ainda está na árvore, e a transição reinscreve nele:
/// `A TextEditingController was used after being disposed`. Com o controller no
/// `State`, quem escolhe a hora é o framework, depois que a rota sai de fato.
class _DialogoDeUrl extends StatefulWidget {
  const _DialogoDeUrl();

  @override
  State<_DialogoDeUrl> createState() => _DialogoDeUrlState();
}

class _DialogoDeUrlState extends State<_DialogoDeUrl> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Instalar de URL'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Endereço do catálogo', hintText: 'https://exemplo.org/catalogo.json'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: const Text('Instalar')),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  final int indice;
  final Addon addon;
  final AddonCoverage cobertura;

  const _Linha({super.key, required this.indice, required this.addon, required this.cobertura});

  @override
  Widget build(BuildContext context) {
    final n = cobertura.consoles.length;
    return ListTile(
      leading: const Icon(Icons.extension_outlined),
      title: Text(addon.name),
      subtitle: Row(
        children: [
          Text(n == 0 ? 'Nenhum console' : '$n console${n == 1 ? '' : 's'}'),
          if (cobertura.authConsoles.isNotEmpty) ...[
            const SizedBox(width: 8),
            const Chip(
              label: Text('conta'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A alça é o único ponto que arrasta, e por isso
          // `buildDefaultDragHandles` é falso lá em cima: com ele ligado, a
          // linha inteira arrasta e o toque que abre o detalhe vira um arrasto
          // de um pixel.
          ReorderableDragStartListener(index: indice, child: const Icon(Icons.drag_handle)),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddonDetailScreen(addonId: addon.id)),
      ),
    );
  }
}
