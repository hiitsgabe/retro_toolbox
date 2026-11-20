import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/fpkgi_server_service.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/widgets/file_browser.dart' show errorReason;
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/settings/ia_credentials_setting.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Controls the embedded FPKGi server and shows the connection details to
/// enter on the PS4 once it is running.
class FpkgiServerScreen extends ConsumerStatefulWidget {
  const FpkgiServerScreen({super.key});

  @override
  ConsumerState<FpkgiServerScreen> createState() => _FpkgiServerScreenState();
}

class _FpkgiServerScreenState extends ConsumerState<FpkgiServerScreen> with ServerToggle {
  static const _info = InfoButton(
    icon: Icons.cloud_upload_rounded,
    title: 'FPKGi Server',
    text: 'Hosts your PS4 library over the local network as an FPKGi shop. Packages and covers stream through this device with your Internet Archive sign-in, '
        'so the PS4 needs no credentials. Both must be on the same network. config.json holds this device\'s address: save it again if the address changes.',
  );

  /// This visit's saves of config.json, newest first.
  final _log = <ActivityEntry>[];

  static String configJson(String url) => const JsonEncoder.withIndent('  ').convert({
        'FILTERING': {
          'CONTENT': 'all',
          'SORT': {'type': 'name', 'ascending': true},
          'REGIONS': ['Asia', 'Europe', 'Japan', 'USA'],
        },
        'PREFERENCES': {
          'DOWNLOADS': {
            'directDownload': false,
            'downloadPath': '/user/data/FPKGi/Downloads/',
            'installAfter': true,
            'deleteAfter': true,
            'deleteOnCancel': true,
          },
          'APPLICATION': {
            'background_uri': 'false',
            'backgroundMusic': false,
            'populateViaWeb': true,
            'enableUpdates': false,
          },
          'CONTENT_URLS': {
            'PS1': null,
            'PS2': null,
            'PSP': null,
            'PS5': null,
            'games': url,
            'apps': null,
            'updates': null,
            'DLC': null,
            'demos': null,
            'homebrew': null,
            'emulators': null,
            'themes': null,
          },
        },
      });

  Future<void> _saveConfig(String url) async {
    final json = configJson(url);
    final path = await pickSavePath(context, title: 'Save FPKGi config.json', fileName: 'config.json', bytes: Uint8List.fromList(utf8.encode(json)));
    if (path == null || !mounted) return;
    String? error;
    // Only iOS' save dialog writes the bytes itself.
    if (!Platform.isIOS) {
      try {
        File(path).writeAsStringSync(json);
      } catch (e) {
        error = 'Could not save config.json: $e';
      }
    }
    if (!mounted) return;
    setState(() => _log.insert(0, ActivityEntry(error ?? 'Saved config.json', detail: error == null ? path : null, tone: error == null ? KitTone.success : KitTone.error)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fpkgiServerProvider);
    final notifier = ref.read(fpkgiServerProvider.notifier);
    final addresses = orderAddresses(state.addresses, ref.watch(settingsProvider).preferredLocalIp);
    final host = state.running ? addresses.firstOrNull : null;
    final iaReady = ref.watch(settingsProvider).iaAccessKey?.isNotEmpty ?? false;
    final ps4 = ref.watch(appStateProvider).consolesList.where(FpkgiServerService.isPs4Console).toList();
    // Only an Internet Archive source needs IA credentials; a PS4 catalog
    // served from anywhere else downloads without them.
    final needsIa = ps4.any((c) => c.usesInternetArchive);
    final hasPs4 = ps4.isNotEmpty;
    final pill = serverStateOf(running: state.running, starting: starting, error: state.error);
    final detail = transfersLabel(state.activeTransfers);
    String urlOf(String ip) => 'http://$ip:${state.port}/games.json';

    final hero = host == null
        ? AddressHero(state: pill, address: '', stateDetail: detail, label: 'Content URL')
        : AddressHero.url(
            urlOf(host),
            state: pill,
            stateDetail: detail,
            otherAddresses: addresses.length - 1,
            onOtherAddresses: () => showOtherAddresses(context, area: AppArea.servers, addresses: [
              for (final ip in addresses.skip(1)) AddressChoice(urlOf(ip), actions: [KitAction('Save config.json', () => _saveConfig(urlOf(ip)))]),
            ]),
          );

    return KitScaffold(
      title: 'FPKGi Server',
      subtitle: 'Your PS4 library as an FPKGi store',
      icon: Icons.cloud_upload_rounded,
      glyph: PixelIcons.fpkgi,
      area: AppArea.servers,
      info: _info,
      body: KitColumns(
        start: [
          if (!hasPs4) const StatusPanel.missingRequirement(title: 'No PS4 system in the catalog', detail: 'Add the PlayStation 4 system to your catalog first.'),
          if (needsIa && !iaReady)
            StatusPanel.missingRequirement(
              title: 'Internet Archive sign-in required',
              detail: 'The PS4 FPKG items are access-restricted; enter your IA keys.',
              actionLabel: 'Add keys',
              onAction: () => showKitSheet<void>(context, area: AppArea.servers, title: 'Internet Archive keys', subtitle: 'For the PS4 downloads', builder: (_) => const IaCredentialsSetting()),
            ),
          hero,
          if (state.error != null && !state.running) StatusPanel.error(line: 'The server did not start: ${errorReason(state.error!)}', details: state.error),
          ConfigFileSlot(
            fileName: 'config.json',
            destination: '/user/data/FPKGi/ on the PS4',
            saveLabel: 'Save config.json',
            onSave: host == null ? null : () => _saveConfig(urlOf(host)),
          ),
          OptionList(children: [PortOption(port: state.port, onChanged: notifier.setPort, lockedReason: state.running ? lockedWhileRunning : null)]),
        ],
        end: [
          const KitLabel('On the PS4'),
          const Steps(
            steps: ['Open FPKGi on the PS4: it reads the store from here'],
            firstTimeLabel: 'Set up the PS4 (once)',
            firstTime: [
              'Install FPKGi and FPKGi Data on the PS4 (from /data/pkg), then open FPKGi once.',
              'Save config.json here, then copy it to /user/data/FPKGi/ on the PS4 with FTP.',
              'In FPKGi press Triangle, turn on "Populate via web", press Triangle again to save.',
              'Reopen FPKGi and browse like a store (L2/R2 switch category).',
            ],
          ),
          if (state.running || _log.isNotEmpty)
            ActivityPanel(count: state.activeTransfers, countLabel: detail ?? 'Idle', entries: _log, emptyText: state.activeTransfers > 0 ? 'The PS4 is downloading from here' : 'No transfers right now'),
        ],
      ),
      actionBar: ActionBar(
        // Off stays reachable; on needs a PS4 system (the panel says so).
        primary: serverAction(
          running: state.running,
          starting: starting,
          onToggle: hasPs4 || state.running ? () => toggleServer(running: state.running, start: notifier.enable, stop: notifier.disable) : null,
        ),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: !hasPs4 && !state.running ? 'Add the PS4 system to your catalog first' : (state.running ? 'Serving on port ${state.port}' : 'Port ${state.port}'),
      ),
    );
  }
}
