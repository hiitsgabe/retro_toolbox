import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/providers/update_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/about/info_card.dart';
import 'package:retro_toolbox/widgets/about/expandable_info_card.dart';
import 'package:retro_toolbox/widgets/about/update_card.dart';
import 'package:retro_toolbox/widgets/about/play_fair_card.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// About: the version in the header, the update state and Play fair, then
/// the links (source, authors, credits, support).
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _packageInfo = info);
    ref.read(updateProvider.notifier).checkOnOpen(info.version);
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final version = _packageInfo?.version;
    return KitScaffold(
      title: 'About',
      subtitle: version == null ? null : 'Version $version',
      icon: Icons.info_outline,
      glyph: PixelIcons.info,
      area: AppArea.info,
      body: KitColumns(
        start: [
          UpdateCard(currentVersion: version),
          const PlayFairCard(),
        ],
        end: [
          KitPanel(children: [
            InfoCard(
              icon: Icons.code_rounded,
              title: 'Open Source',
              subtitle: 'Contributions welcome at hiitsgabe/retro_toolbox',
              url: 'https://github.com/hiitsgabe/retro_toolbox',
              onTap: () => _copyToClipboard(context, 'https://github.com/hiitsgabe/retro_toolbox'),
            ),
            ExpandableInfoCard(
              icon: Icons.person_rounded,
              title: 'Authors',
              items: const [
                InfoItem('rafaismyname', 'rafaismy.name', 'https://rafaismy.name'),
                InfoItem('hiitsgabe', 'gabeismy.name', 'https://gabeismy.name'),
              ],
              onItemTap: (url) => _copyToClipboard(context, url),
            ),
            ExpandableInfoCard(
              icon: Icons.favorite_rounded,
              title: 'Credits',
              items: const [
            InfoItem('nsz', 'NSZ decompression by nicoboss - github.com/nicoboss/nsz', 'https://github.com/nicoboss/nsz'),
            InfoItem('chdman', 'CHD conversion by the MAME project (BSD-3) - mamedev.org', 'https://www.mamedev.org'),
            InfoItem('3dsconv', '3DS→CIA conversion by ihaveamac (MIT) - github.com/ihaveamac/3dsconv', 'https://github.com/ihaveamac/3dsconv'),
            InfoItem('pyaes', 'AES for 3dsconv - pypi.org/project/pyaes', 'https://pypi.org/project/pyaes'),
            InfoItem('0x0', 'Ephemeral storage - 0x0.st', 'https://0x0.st'),
            InfoItem('EmulationStation Carbon', 'Console logos by Rookervik', 'https://github.com/RetroPie/es-theme-carbon'),
            InfoItem('Art Book Next', 'Console logos by Anthony Caccese (CC-BY-NC-SA)', 'https://github.com/anthonycaccese/es-theme-art-book-next'),
            InfoItem('Chakra Petch', 'Font by Cadson Demak (OFL)', 'https://fonts.google.com/specimen/Chakra+Petch'),
            InfoItem('flutter', 'flutter.dev', 'https://flutter.dev'),
            InfoItem('serious_python', 'pub.dev/packages/serious_python', 'https://pub.dev/packages/serious_python'),
            InfoItem('file_picker', 'pub.dev/packages/file_picker', 'https://pub.dev/packages/file_picker'),
            InfoItem('background_downloader', 'pub.dev/packages/background_downloader', 'https://pub.dev/packages/background_downloader'),
            InfoItem('flutter_riverpod', 'pub.dev/packages/flutter_riverpod', 'https://pub.dev/packages/flutter_riverpod'),
            InfoItem('shared_preferences', 'pub.dev/packages/shared_preferences', 'https://pub.dev/packages/shared_preferences'),
            InfoItem('url_launcher', 'pub.dev/packages/url_launcher', 'https://pub.dev/packages/url_launcher'),
            InfoItem('path_provider', 'pub.dev/packages/path_provider', 'https://pub.dev/packages/path_provider'),
            InfoItem('permission_handler', 'pub.dev/packages/permission_handler', 'https://pub.dev/packages/permission_handler'),
            InfoItem('archive', 'pub.dev/packages/archive', 'https://pub.dev/packages/archive'),
            InfoItem('flutter_archive', 'pub.dev/packages/flutter_archive', 'https://pub.dev/packages/flutter_archive'),
            InfoItem('rar', 'pub.dev/packages/rar', 'https://pub.dev/packages/rar'),
            InfoItem('qr_flutter', 'pub.dev/packages/qr_flutter', 'https://pub.dev/packages/qr_flutter'),
            InfoItem('flutter_foreground_task', 'pub.dev/packages/flutter_foreground_task', 'https://pub.dev/packages/flutter_foreground_task'),
            InfoItem('package_info_plus', 'pub.dev/packages/package_info_plus', 'https://pub.dev/packages/package_info_plus'),
            InfoItem('cached_network_image', 'pub.dev/packages/cached_network_image', 'https://pub.dev/packages/cached_network_image'),
            InfoItem('rapidfuzz', 'pub.dev/packages/rapidfuzz', 'https://pub.dev/packages/rapidfuzz'),
            InfoItem('photo_view', 'pub.dev/packages/photo_view', 'https://pub.dev/packages/photo_view'),
            InfoItem('disk_space_2', 'pub.dev/packages/disk_space_2', 'https://pub.dev/packages/disk_space_2'),
              ],
              onItemTap: (url) => _copyToClipboard(context, url),
            ),
            InfoCard(
              icon: Icons.coffee_rounded,
              title: 'Buy me a coffee',
              subtitle: 'Free and made in our spare time: a coffee keeps it going',
              url: 'https://buymeacoffee.com/hiitsgabe',
              onTap: () => _copyToClipboard(context, 'https://buymeacoffee.com/hiitsgabe'),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Made in NYC and Toronto', textAlign: TextAlign.center, style: KitType.of(context).subtitle.copyWith(fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }
}
