import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/widgets/file_browser.dart' show errorReason;
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/settings/console_auth_setting.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Controls the embedded Tinfoil shop server and shows the connection
/// details to enter on the Switch once it is running.
class TinfoilServerScreen extends ConsumerStatefulWidget {
  const TinfoilServerScreen({super.key});

  @override
  ConsumerState<TinfoilServerScreen> createState() => _TinfoilServerScreenState();
}

class _TinfoilServerScreenState extends ConsumerState<TinfoilServerScreen> with ServerToggle {
  static const _info = InfoButton(
    icon: Icons.cloud_upload_rounded,
    title: 'Tinfoil Server',
    text: 'Hosts your game library over the local network so Tinfoil on your console can browse and install titles directly from this device. '
        'Both must be on the same network. A "Fast install" location in the File Browser lists only the games already on this device and installs '
        'them straight from its storage; if it does not appear, add one with Path /Fast install/.',
  );

  Future<void> _signIn(Console c) => showKitSheet<void>(context, area: AppArea.servers, title: '${c.name} sign-in', subtitle: 'Needed to download its games', builder: (_) => ConsoleAuthSetting(console: c));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tinfoilServerProvider);
    final notifier = ref.read(tinfoilServerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final addresses = orderAddresses(state.addresses, settings.preferredLocalIp);
    final host = state.running ? addresses.firstOrNull : null;
    final pill = serverStateOf(running: state.running, starting: starting, error: state.error);
    final detail = transfersLabel(state.activeTransfers);

    final switches = ref.watch(appStateProvider).consolesList.where(TinfoilServerService.isSwitchConsole).toList();
    bool authed(Console c) => (settings.consoleSettings[c.id]?.authToken?.isNotEmpty ?? false) || ((c.auth?['token'] as String?)?.isNotEmpty ?? false);
    final auth = switches.where((c) => c.hasTokenAuth).toList();
    final locked = state.running ? lockedWhileRunning : null;

    final hero = host == null
        ? AddressHero(state: pill, address: '', stateDetail: detail)
        : AddressHero.hostPort(
            state: pill,
            stateDetail: detail,
            host: host,
            port: state.port,
            otherAddresses: addresses.length - 1,
            onOtherAddresses: () => showOtherAddresses(context, area: AppArea.servers, addresses: [for (final ip in addresses.skip(1)) AddressChoice(ip)]),
          );

    return KitScaffold(
      title: 'Tinfoil Server',
      subtitle: 'Install Switch games from here with Tinfoil',
      icon: Icons.cloud_upload_rounded,
      glyph: PixelIcons.tinfoil,
      area: AppArea.servers,
      info: _info,
      body: KitColumns(
        start: [
          // A source that cannot download is what the user must fix first.
          for (final c in auth)
            if (!authed(c))
              StatusPanel.missingRequirement(
                title: 'Sign in to ${c.name} to serve its games',
                detail: 'Required to download',
                actionLabel: 'Sign in',
                onAction: () => _signIn(c),
              ),
          hero,
          if (state.error != null && !state.running) StatusPanel.error(line: 'The server did not start: ${errorReason(state.error!)}', details: state.error),
          KitPanel(children: [
            Slot(
              label: 'Serving',
              icon: Icons.inventory_2_outlined,
              glyph: PixelIcons.games,
              value: switches.isEmpty ? null : switches.map((c) => c.name).join(', '),
              emptyText: 'No Switch system in your catalog',
            ),
          ]),
          OptionList(children: [
            PortOption(port: state.port, onChanged: notifier.setPort, lockedReason: locked),
            for (final c in auth)
              if (authed(c)) OptionAction(title: '${c.name} sign-in', subtitle: 'Authenticated', value: 'Signed in', onTap: () => _signIn(c)),
          ]),
        ],
        end: [
          const KitLabel('In Tinfoil'),
          const Steps(
            steps: ['Open the File Browser, then this server', 'Your games show in New Games'],
            firstTime: [
              'File Browser, then New',
              'Protocol http, then the Host and Port shown here',
              'Save. Your games show up under New Games',
            ],
          ),
          if (state.running)
            ActivityPanel(
              count: state.activeTransfers,
              countLabel: detail ?? 'Idle',
              emptyText: state.activeTransfers > 0 ? 'Tinfoil is downloading from here' : 'No transfers right now',
            ),
        ],
      ),
      actionBar: ActionBar(
        primary: serverAction(
          running: state.running,
          starting: starting,
          onToggle: () => toggleServer(running: state.running, start: notifier.enable, stop: notifier.disable),
        ),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: state.running ? 'Serving on port ${state.port}' : 'Port ${state.port}',
      ),
    );
  }
}
