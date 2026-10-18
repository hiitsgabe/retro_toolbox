import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/link_download_screen.dart';
import 'package:retro_toolbox/services/link_inbox_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeServer implements LinkInboxServer {
  final ctrl = StreamController<String>.broadcast();
  int? _port;
  @override
  Stream<String> get links => ctrl.stream;
  @override
  bool get running => _port != null;
  @override
  int? get port => _port;
  @override
  Future<void> start(int port) async => _port = port;
  @override
  Future<void> stop() async => _port = null;
}

class _FakeQueue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _FakeQueue() : super(const TaskQueueState());
  final enqueued = <(String, TaskType, Map<String, dynamic>)>[];
  @override
  void enqueue(String taskId, TaskType type, Map<String, dynamic> params) => enqueued.add((taskId, type, params));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => Directory.systemTemp.path);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));

  Future<(ProviderContainer, _FakeServer)> pump(WidgetTester t, {List<Override> overrides = const []}) async {
    await t.binding.setSurfaceSize(const Size(640, 480));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final server = _FakeServer();
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: LinkDownloadScreen(server: server, addresses: () async => ['192.168.1.42'])),
    ));
    await t.pump();
    await t.pump();
    return (c, server);
  }

  Finder downloadButton() => find.ancestor(of: find.text('Download'), matching: find.byWidgetPredicate((w) => w is FilledButton));

  testWidgets('a link from the phone fills the field and starts nothing', (t) async {
    final (c, server) = await pump(t);
    expect(server.port, linkInboxDefaultPort);
    server.ctrl.add('https://h/a.zip');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(t.widget<TextField>(find.byType(TextField).first).controller!.text, 'https://h/a.zip');
    // Shown in full under the field too, where a long link would be cut off.
    expect(find.text('https://h/a.zip'), findsNWidgets(2));
    expect(find.text('Link received from your phone. Press Download to start.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'a.zip'), findsOneWidget);
    expect(c.read(taskQueueProvider).tasks, isEmpty);
    expect(t.widget<FilledButton>(downloadButton()).onPressed, isNotNull);
    // The queue polls on a periodic timer; stop it before the test ends.
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a long link from the phone is shown in full', (t) async {
    final (_, server) = await pump(t);
    final link = 'https://h/a.zip?sig=${'x' * 600}';
    server.ctrl.add(link);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    final helper = find.descendant(of: find.byType(InputDecorator).first, matching: find.byWidgetPredicate((w) => w is Text && w.data == link));
    final paragraph = t.renderObject<RenderParagraph>(helper);
    expect(paragraph.didExceedMaxLines, isFalse, reason: 'helper text was cut off');
    expect(t.takeException(), isNull);
  });

  testWidgets('a non-http link is refused', (t) async {
    await pump(t);
    await t.enterText(find.byType(TextField).first, 'ftp://h/a');
    await t.pump();
    expect(find.text('Enter an http or https link'), findsOneWidget);
    expect(t.widget<FilledButton>(downloadButton()).onPressed, isNull);
  });

  testWidgets('the phone card shows the address with the port', (t) async {
    await pump(t);
    expect(find.textContaining(':9094'), findsOneWidget);
    expect(find.textContaining('192.168.1.42'), findsOneWidget);
  });

  testWidgets('Download queues the link; a finished archive offers Extract here', (t) async {
    final queue = _FakeQueue();
    final (c, server) = await pump(t, overrides: [taskQueueProvider.overrideWith((ref) => queue)]);
    server.ctrl.add(' https://h/a.zip ');
    await t.pump();
    await t.tap(downloadButton());
    await t.pump();
    final (id, type, params) = queue.enqueued.single;
    expect(type, TaskType.remoteTransfer);
    expect(params['label'], 'a.zip');
    final state = c.read(gameStateManagerProvider)[id]!;
    expect(state.outputPath, endsWith('${Platform.pathSeparator}a.zip'));

    c.read(gameStateManagerProvider.notifier).updateExtractionState(id, ExtractionStatus.completed, 1);
    await t.pump();
    // Let the earlier snackbars (link received, added to the task list) go by.
    for (var i = 0; i < 40 && find.text('a.zip downloaded').evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('a.zip downloaded'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 500)); // slide-in
    await t.tap(find.text('Extract here'));
    await t.pump();
    final (_, extractType, extractParams) = queue.enqueued.last;
    expect(extractType, TaskType.archiveExtraction);
    expect(extractParams['archivePath'], state.outputPath);
  });
}
