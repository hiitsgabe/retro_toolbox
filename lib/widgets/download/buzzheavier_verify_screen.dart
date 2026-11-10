import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Full-screen in-app browser for Cloudflare-verified buzzheavier downloads.
///
/// The site's resolution endpoints sit behind a challenge that plain HTTP
/// clients never pass (Cloudflare fingerprints the TLS stack, not just the
/// cookie), so the htmx call that yields the direct link runs INSIDE the
/// webview, in page context: fetch the hx-get download endpoint and read the
/// `Hx-Redirect` response header. [url] is the file page; the direct link is
/// only served by the tokened ts. host, which plain HTTP clients can get.
/// Pops with the direct URL, or null when the user backs out.
class BuzzheavierVerifyScreen extends StatefulWidget {
  const BuzzheavierVerifyScreen({super.key, required this.url});

  final String url;

  static Future<String?> push(BuildContext context, String url) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => BuzzheavierVerifyScreen(url: url)),
    );
  }

  @override
  State<BuzzheavierVerifyScreen> createState() => _BuzzheavierVerifyScreenState();
}

class _BuzzheavierVerifyScreenState extends State<BuzzheavierVerifyScreen> {
  InAppWebViewController? _controller;
  Timer? _poll;
  bool _popped = false;
  String _status = 'Carregando a página do arquivo…';

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Runs the htmx download call in page context and grabs Hx-Redirect.
  Future<void> _tryResolve(InAppWebViewController controller) async {
    if (_popped) return;
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: """
          const a = document.querySelector("a[hx-get*='/download']");
          if (!a) return null;
          const res = await fetch(location.origin + a.getAttribute("hx-get"), {
            headers: { "hx-request": "true" },
            credentials: "include",
          });
          return res.headers.get("hx-redirect");
        """,
      );
      final direct = result?.value;
      if (direct is! String || direct.isEmpty) {
        if (mounted) {
          setState(() => _status = 'Verificação pendente — confirme no aviso acima. O download continua sozinho em seguida.');
        }
        return;
      }
      _popped = true;
      _poll?.cancel();
      if (mounted) Navigator.of(context).pop(direct);
    } catch (e) {
      debugPrint('Buzzheavier verification resolve failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificação humana — Buzzheavier'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              onWebViewCreated: (controller) {
                _controller = controller;
                setState(() => _status = 'Página carregada — aguardando a verificação…');
              },
              onLoadStop: (controller, url) async {
                await _tryResolve(controller);
                _poll ??= Timer.periodic(const Duration(seconds: 1), (_) {
                  final c = _controller;
                  if (c != null) _tryResolve(c);
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _status,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
