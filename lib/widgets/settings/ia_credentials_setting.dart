import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/settings_provider.dart';

const _iaLoginUrl = 'https://archive.org/services/xauthn/?op=login';

class IaCredentialsSetting extends ConsumerStatefulWidget {
  const IaCredentialsSetting({super.key});

  @override
  ConsumerState<IaCredentialsSetting> createState() => _IaCredentialsSettingState();
}

class _IaCredentialsSettingState extends ConsumerState<IaCredentialsSetting> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      final request = await client.postUrl(Uri.parse(_iaLoginUrl));
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      final body = 'email=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}';
      request.contentLength = utf8.encode(body).length;
      request.write(body);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (data['success'] == true) {
        final values = data['values'] as Map<String, dynamic>?;
        final s3 = values?['s3'] as Map<String, dynamic>?;
        final accessKey = s3?['access'] as String?;
        final secretKey = s3?['secret'] as String?;
        // Session cookies unlock downloads from "loggedin"-restricted items.
        final cookies = (values?['cookies'] as Map<String, dynamic>?)
            ?.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
        if (accessKey != null && secretKey != null) {
          await ref.read(settingsProvider.notifier).setIaCredentials(accessKey, secretKey, cookies: cookies);
          if (mounted) {
            _emailController.clear();
            _passwordController.clear();
          }
        } else {
          setState(() => _error = 'Login succeeded but no credentials were returned.');
        }
      } else {
        final reason = (data['values'] as Map<String, dynamic>?)?['reason'] as String?;
        setState(() => _error = reason ?? 'Login failed.');
      }
    } catch (e) {
      setState(() => _error = 'Connection error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(settingsProvider.notifier).clearIaCredentials();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isLoggedIn = settings.hasIaCredentials;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLoggedIn) ...[
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Logged in to Internet Archive',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Log out'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
          const Text(
            'Your credentials are saved and will be used for restricted downloads.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ] else ...[
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: !_loading,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            enabled: !_loading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _login,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.login, size: 18),
              label: Text(_loading ? 'Logging in…' : 'Log in'),
            ),
          ),
        ],
      ],
    );
  }
}
