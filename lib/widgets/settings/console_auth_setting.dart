import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/utils/network.dart';
import 'package:url_launcher/url_launcher.dart';

class ConsoleAuthSetting extends ConsumerStatefulWidget {
  final Console console;

  /// De qual addon é esta conta. O mesmo console pode ser servido por dois
  /// addons, com credenciais diferentes, e o formulário é de um deles.
  final String addonId;

  /// Chamado depois de o token ir para o cofre, com o valor novo (vazio quando
  /// o usuário deslogou).
  ///
  /// Existe porque quem desenha o estado de conexão **fora** deste formulário
  /// não tem como saber que ele gravou: o cofre não notifica, e para addon de
  /// terceiro `setAddonToken` nem chega a mexer em `settingsProvider`
  /// (Task 19). Opcional, porque os dois outros chamadores desenham o estado
  /// aqui dentro.
  final void Function(String token)? onSaved;

  const ConsoleAuthSetting({super.key, required this.console, required this.addonId, this.onSaved});

  @override
  ConsumerState<ConsoleAuthSetting> createState() => _ConsoleAuthSettingState();
}

class _ConsoleAuthSettingState extends ConsumerState<ConsoleAuthSetting> {
  final TextEditingController _tokenController = TextEditingController();
  final Map<String, TextEditingController> _signinControllers = {};

  /// O que está guardado no cofre agora. Não vem de `settingsProvider`: o
  /// espelho de lá é só do addon embutido (Task 19).
  String _saved = '';
  bool _carregando = true;
  bool _obscure = true;
  bool _dirty = false;
  bool _signingIn = false;

  List<String> get _signinParams => List<String>.from(widget.console.authSignin?['params'] as List? ?? const []);

  @override
  void initState() {
    super.initState();
    for (final param in _signinParams) {
      _signinControllers[param] = TextEditingController();
    }
    _carregarToken();
  }

  /// O cofre é assíncrono e `initState` não é, então o formulário nasce em
  /// estado de carga. Um quadro com barra é melhor que um quadro com o campo
  /// vazio: o campo vazio diz "você não tem conta" para quem tem.
  Future<void> _carregarToken() async {
    final token = await ref.read(settingsProvider.notifier).readAddonToken(widget.addonId, widget.console.id);
    if (!mounted) return;
    setState(() {
      _saved = token;
      _tokenController.text = token;
      _carregando = false;
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    for (final c in _signinControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar(String token) async {
    await ref.read(settingsProvider.notifier).setAddonToken(widget.addonId, widget.console.id, token);
    if (!mounted) return;
    setState(() {
      _saved = token;
      _dirty = false;
    });
    widget.onSaved?.call(token);
  }

  Future<void> _signin() async {
    setState(() => _signingIn = true);
    try {
      final token = await signinForToken(
        widget.console.authSignin!,
        {for (final e in _signinControllers.entries) e.key: e.value.text.trim()},
      );
      _tokenController.text = token;
      await _guardar(token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in, token saved.'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 4)),
        );
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _save() async {
    await _guardar(_tokenController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auth token saved.'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _clear() async {
    _tokenController.clear();
    await _guardar('');
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final hasToken = _saved.isNotEmpty;

    // Once a token is saved, show a compact "signed in" state (like the IA
    // login) instead of the sign-in form. Log out clears it to reveal inputs.
    if (hasToken && !_dirty) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Signed in', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          TextButton.icon(
            onPressed: _clear,
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Log out'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      );
    }

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
        if (widget.console.authSignin != null) ...[
          for (final param in _signinParams) ...[
            TextField(
              controller: _signinControllers[param],
              obscureText: param.toLowerCase().contains('password'),
              decoration: InputDecoration(
                labelText: param[0].toUpperCase() + param.substring(1),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (widget.console.authSignin!['register_url'] != null)
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(widget.console.authSignin!['register_url'] as String)),
                  child: const Text('Create account'),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _signingIn ? null : _signin,
                icon: _signingIn
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login, size: 16),
                label: const Text('Sign in'),
              ),
            ],
          ),
          // Pasting a raw token is the fallback — tuck it under Advanced.
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: EdgeInsets.zero,
            title: const Text('Advanced', style: TextStyle(fontSize: 13)),
            children: [_tokenSection(context, hasToken)],
          ),
        ] else
          _tokenSection(context, hasToken),
      ],
    );
  }

  Widget _tokenSection(BuildContext context, bool hasToken) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
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
      ],
    );
  }
}
