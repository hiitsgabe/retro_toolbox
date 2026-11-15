import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/update_provider.dart';
import 'package:retro_toolbox/services/update_service.dart';
import 'package:retro_toolbox/utils/server_mode.dart';
import 'package:retro_toolbox/widgets/about/update_card.dart';

const _cmd = 'docker compose pull && docker compose up -d';

class _Available extends UpdateNotifier {
  _Available() : super(UpdateService(portRoot: '/nowhere'), handheld: false, os: 'linux') {
    state = UpdateState(UpdatePhase.available,
        release: ReleaseInfo(version: '0.3.0', htmlUrl: 'u', notes: '', assets: const []));
  }
}

Future<void> _pump(WidgetTester t) => t.pumpWidget(ProviderScope(
      overrides: [updateProvider.overrideWith((ref) => _Available())],
      child: const MaterialApp(home: Scaffold(body: UpdateCard(currentVersion: '0.2.0'))),
    ));

void main() {
  tearDown(() => ServerMode.current = false);

  testWidgets('server mode points at docker compose pull and copies it', (t) async {
    ServerMode.current = true;
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(t);
    expect(find.text('Update the Docker image: $_cmd'), findsOneWidget);
    expect(find.text('Open release page'), findsNothing);
    await t.tap(find.widgetWithText(FilledButton, 'Copy command'));
    expect(copied, _cmd);
  });

  testWidgets('outside server mode keeps Open release page', (t) async {
    ServerMode.current = false;
    await _pump(t);
    expect(find.widgetWithText(FilledButton, 'Open release page'), findsOneWidget);
    expect(find.text('Copy command'), findsNothing);
  });
}
