import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

import 'support.dart';

/// The kit's parts put together as the screens will use them: a tool in
/// each status, a server, a wizard and a list tool. Sample data only.
///
///   SCREENSHOTS=1 flutter test test/screenshots/kit_test.dart --dart-define=DEVICE=odin2 --dart-define=OUT=/tmp/shots

const _ff = 'Final Fantasy VII (USA) (Disc 1)';

Widget _tool(StatusPanel status) => KitScaffold(
      title: 'CHD Converter',
      subtitle: 'Compress disc images to .chd, or extract them',
      icon: Icons.album_outlined,
      glyph: PixelIcons.chd,
      area: AppArea.tools,
      info: const InfoButton(icon: Icons.album_outlined, text: 'chdman packs disc images into one compressed .chd.'),
      body: KitColumns(
        endFirstWhenStacked: true,
        start: [
          const KitLabel('Input'),
          KitPanel(children: [
            Slot(label: 'Disc image', path: '/storage/emulated/0/ROMs/psx/Crash Bandicoot (USA).cue', onPick: () {}, autofocus: true),
            Slot(label: 'Save to', folder: true, path: '/storage/emulated/0/ROMs/psx', onPick: () {}),
          ]),
          const KitLabel('Options'),
          OptionList(children: [
            OptionToggle(title: 'Delete original', subtitle: 'Only after it converts, with the .cue tracks', value: true, onChanged: (_) {}),
            OptionExpander(subtitle: '.iso as DVD or CD', children: [OptionToggle(title: 'CD for AetherSX2', value: false, onChanged: (_) {})]),
          ]),
        ],
        end: [status],
      ),
      actionBar: ActionBar(
        primary: KitAction('Compress to CHD', () {}),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: 'Crash Bandicoot (USA).cue to .chd',
      ),
    );

const _working = StatusPanel.working(items: [
  WorkItem(_ff, progress: 0.62),
  WorkItem('Final Fantasy VII (USA) (Disc 2)', state: WorkState.queued),
  WorkItem('Metal Gear Solid (USA) (Disc 1)', state: WorkState.done),
]);

final _statuses = <String, StatusPanel>{
  'working': _working,
  'missing': StatusPanel.missingRequirement(
    title: 'chdman not found',
    detail: 'CHD needs chdman, from the MAME tools.',
    actionLabel: 'Locate chdman',
    onAction: () {},
    linkLabel: 'How to get it',
    onLink: () {},
  ),
  'done': const StatusPanel.done(summary: 'Compressed 3 discs, saved 1.2 GB', problems: [
    Problem('Metal Gear Solid (USA) (Disc 2).cue', 'A .chd with this name is already there'),
  ]),
  'error': const StatusPanel.error(line: 'chdman stopped on Crash Bandicoot (USA).cue', details: 'Error: file not found: Crash Bandicoot (USA) (Track 2).bin'),
};

Widget _server() => KitScaffold(
      title: 'Tinfoil Server',
      subtitle: 'Install games on a Switch over the local network',
      icon: Icons.cloud_upload_outlined,
      glyph: PixelIcons.tinfoil,
      area: AppArea.servers,
      info: const InfoButton(icon: Icons.cloud_upload_outlined, text: 'Tinfoil reads this device as a shop.'),
      body: KitColumns(
        start: [
          AddressHero.hostPort(host: '192.168.1.42', port: 9092, state: ServerState.on, stateDetail: '1 transfer', otherAddresses: 1, onOtherAddresses: () {}),
          KitPanel(children: [Slot(label: 'Serving', value: '412 games, 96 updates, 140 DLC', verb: 'View', icon: Icons.inventory_2_outlined, glyph: PixelIcons.games, onPick: () {})]),
        ],
        end: const [
          KitLabel('In Tinfoil'),
          Steps(
            steps: ['File Browser, then this server', 'New games show in New Games'],
            firstTime: ['File Browser, new location', 'Protocol http, host and port as shown', 'Save'],
          ),
          ActivityPanel(count: 1, countLabel: '1 transfer', entries: [
            ActivityEntry('Celeste [v0].nsz', detail: 'Sending, 40%', time: '12:04', tone: KitTone.accent),
            ActivityEntry('Hollow Knight [v0].nsp', detail: 'Sent, 7.1 GB', time: '11:58', tone: KitTone.success),
          ]),
        ],
      ),
      actionBar: ActionBar(primary: KitAction('Stop server', () {}), hints: const [KitHint(PadButton.b, 'Back')], summary: 'On for 12 min'),
    );

Widget _wizardCatalog() => WizardShell(
      name: 'Library setup',
      step: 0,
      count: 3,
      stepName: 'Catalog',
      glyph: PixelIcons.games,
      icon: Icons.sports_esports_outlined,
      area: AppArea.games,
      info: const InfoButton(icon: Icons.sports_esports_outlined, text: 'Pick where the consoles come from.'),
      onNext: () {},
      summary: 'Built-in, 12 consoles',
      hints: const [KitHint(PadButton.a, 'Pick')],
      body: KitColumns(
        start: [
          const KitLabel('Where the consoles come from'),
          OptionList(children: [
            for (final (title, sub) in [
              ('Built-in catalog', '12 consoles, works right away'),
              ('From a link', 'A catalog JSON URL'),
              ('From a file', 'Import a JSON file'),
              ('Paste JSON', 'Type or paste it here'),
            ])
              OptionChoice<String>(title: title, subtitle: sub, value: title, groupValue: 'Built-in catalog', onSelected: (_) {}, autofocus: title.startsWith('Built')),
          ]),
        ],
        end: [
          const KitLabel('You will get'),
          KitPanel(padding: const EdgeInsets.all(12), children: [
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final c in ['SNES', 'NES', 'N64', 'GBA', 'Genesis', 'PS1', 'PS2', 'PSP', 'Dreamcast', 'GameCube', 'Switch', '3DS']) KitBadge(c),
            ]),
          ]),
        ],
      ),
    );

Widget _wizardDownloads() => WizardShell(
      name: 'Library setup',
      step: 1,
      count: 3,
      stepName: 'Downloads',
      glyph: PixelIcons.games,
      icon: Icons.sports_esports_outlined,
      area: AppArea.games,
      info: const InfoButton(icon: Icons.sports_esports_outlined, text: 'Where downloads go.'),
      onNext: () {},
      onBack: () {},
      body: KitColumns(start: [
        const KitLabel('Where to save'),
        KitPanel(children: [Slot(label: 'Download folder', folder: true, path: '/storage/emulated/0/ROMs', onPick: () {}, autofocus: true)]),
        const KitLabel('After a download'),
        OptionList(children: [OptionToggle(title: 'Extract after download', subtitle: 'Zip and rar files are unpacked', value: true, onChanged: (_) {})]),
      ]),
    );

Widget _results() => KitScaffold(
      title: 'M3U Playlists',
      subtitle: 'One playlist per multi-disc game',
      icon: Icons.queue_music_outlined,
      glyph: PixelIcons.m3u,
      area: AppArea.tools,
      info: const InfoButton(icon: Icons.queue_music_outlined, text: 'An .m3u lists the discs of a game.'),
      body: KitColumns(
        fillEnd: true,
        start: [
          const KitLabel('Folder'),
          KitPanel(children: [Slot(label: 'Scan', folder: true, path: '/storage/emulated/0/ROMs/psx', onPick: () {}, autofocus: true)]),
          const KitLabel('Options'),
          OptionList(children: [OptionToggle(title: 'Hide the discs', subtitle: 'Move them to a .hidden folder', value: false, onChanged: (_) {})]),
        ],
        end: [
          ResultsList(
            selected: const {'ff', 'mgs'},
            onSelectionChanged: (_) {},
            groups: const [
              ResultGroup('Final Fantasy VII', [ResultRow(id: 'ff', title: 'Final Fantasy VII (USA).m3u', subtitle: '3 discs', badge: 'New', badgeTone: KitTone.accent)]),
              ResultGroup('Metal Gear Solid', [
                ResultRow(id: 'mgs', title: 'Metal Gear Solid (USA) (Rev 1).m3u', subtitle: '2 discs', badge: 'New', badgeTone: KitTone.accent),
                ResultRow(id: 'old', title: 'Metal Gear Solid (USA).m3u', subtitle: 'Already there', badge: 'Exists', selectable: false),
              ]),
            ],
          ),
        ],
      ),
      actionBar: ActionBar(
        primary: KitAction('Create 2 playlists', () {}),
        hints: const [KitHint(PadButton.a, 'Mark'), KitHint(PadButton.select, 'All')],
        summary: '2 of 2 selected',
      ),
    );

void main() {
  screenshotSetUp();

  final screens = <String, (Widget Function(), List<InputMode>)>{
    'tool': (() => _tool(_working), InputMode.values),
    for (final s in ['missing', 'done', 'error']) 'tool_$s': (() => _tool(_statuses[s]!), [InputMode.touch]),
    'server': (_server, InputMode.values),
    'wizard_catalog': (_wizardCatalog, [InputMode.gamepad]),
    'wizard_downloads': (_wizardDownloads, [InputMode.touch]),
    'results': (_results, InputMode.values),
  };

  for (final cards in [CardStyle.classic, CardStyle.switchStyle]) {
    for (final MapEntry(key: name, value: (build, modes)) in screens.entries) {
      for (final mode in modes) {
        testWidgets('kit $name ${cards.name} ${mode.name}', (t) async {
          final c = await launch(t, const Scaffold(), style: AppStyle(cards: cards));
          await push(t, build());
          c.read(inputModeProvider.notifier).state = mode;
          // A key shows the d-pad's focus ring, as after any button press.
          if (mode == InputMode.gamepad) await key(t, LogicalKeyboardKey.shiftLeft);
          c.read(inputModeProvider.notifier).state = mode;
          await frames(t, 3);
          await snap(t, 'kit_${name}_${cards.name}_${mode.name}');
        }, skip: !screenshotsEnabled);
      }
    }
  }
}
