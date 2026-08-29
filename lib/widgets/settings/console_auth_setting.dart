import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/settings_provider.dart';

class ConsoleAuthSetting extends ConsumerStatefulWidget {
  final Console console;

  const ConsoleAuthSetting({super.key, required this.console});

  @override
  ConsumerState<ConsoleAuthSetting> createState() => _ConsoleAuthSettingState();
}

class _ConsoleAuthSettingState extends ConsumerState<ConsoleAuthSetting> {
  late final TextEditingController _tokenController;
  bool _obscure = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(settingsProvider.notifier).getConsoleAuthToken(widget.console.id);
    _tokenController = TextEditingController(text: saved ?? '');
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).setConsoleAuthToken(
          widget.console.id,
          _tokenController.text.trim(),
        );
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auth token saved.'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _clear() async {
    _tokenController.clear();
    await ref.read(settingsProvider.notifier).setConsoleAuthToken(widget.console.id, '');
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(settingsProvider).consoleSettings[widget.console.id]?.authToken ?? '';
    final hasToken = saved.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.console.authMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.console.authMessage!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tokenController,
                obscureText: _obscure,
                onChanged: (_) => setState(() => _dirty = true),
                decoration: InputDecoration(
                  labelText: widget.console.authUsesCookies
                      ? 'Cookie token (${widget.console.authCookieName})'
                      : 'Bearer token',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (hasToken)
              TextButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Save'),
            ),
          ],
        ),
        if (hasToken && !_dirty)
          Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.green, size: 14),
              SizedBox(width: 4),
              Text('Token saved', style: TextStyle(fontSize: 12, color: Colors.green)),
            ],
          ),
      ],
    );
  }
}
