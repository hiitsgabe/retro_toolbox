import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/browser_layout_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/screens/ftp_screen.dart';
import 'package:retro_toolbox/providers/smb_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/smb_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSmb extends StateNotifier<SmbState> implements SmbNotifier {
  _FakeSmb() : super(const SmbState(connected: true, path: '/share'));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFtp extends StateNotifier<FtpState> implements FtpNotifier {
  _FakeFtp() : super(const FtpState(connected: true));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeQueue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _FakeQueue(List<QueuedTask> tasks) : super(TaskQueueState(tasks: tasks));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeExtraction extends StateNotifier<ExtractionState> implements ExtractionNotifier {
  _FakeExtraction(Map<String, ExtractionTaskState> tasks) : super(ExtractionState(tasks: tasks));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

QueuedTask _task(String id, String source, TaskQueueStatus status) => QueuedTask(
      id: id,
      type: TaskType.remoteTransfer,
      status: status,
      createdAt: DateTime(2026),
      params: {'taskId': id, 'verb': 'Downloading', 'label': 'big.bin', 'source': source},
    );

Future<void> pumpSmb(WidgetTester t, List<QueuedTask> tasks, Map<String, ExtractionTaskState> progress, {Widget screen = const SmbScreen()}) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(ProviderScope(
    overrides: [
      smbProvider.overrideWith((ref) => _FakeSmb()),
      ftpProvider.overrideWith((ref) => _FakeFtp()),
      taskQueueProvider.overrideWith((ref) => _FakeQueue(tasks)),
      extractionProvider.overrideWith((ref) => _FakeExtraction(progress)),
      browserLayoutProvider.overrideWith((ref) => BrowserLayoutNotifier()..state = BrowserLayout.list),
    ],
    child: MaterialApp(home: screen),
  ));
  await t.pump();
}

void main() {
  testWidgets('a running queued SMB download shows its progress in the SMB browser', (t) async {
    await pumpSmb(
      t,
      [_task('a', 'smb', TaskQueueStatus.running)],
      {'a': const ExtractionTaskState(taskId: 'a', status: ExtractionStatus.extracting, progress: 0.5)},
    );
    expect(find.text('Downloading big.bin'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
  });

  testWidgets('a waiting queued SMB download shows an indeterminate bar', (t) async {
    await pumpSmb(t, [_task('a', 'smb', TaskQueueStatus.waiting)], {});
    expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
  });

  testWidgets('FTP transfers and finished ones do not show in the SMB browser', (t) async {
    await pumpSmb(t, [_task('a', 'ftp', TaskQueueStatus.running), _task('b', 'smb', TaskQueueStatus.completed)], {});
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a running task is shown in preference to an earlier waiting one', (t) async {
    await pumpSmb(
      t,
      [_task('a', 'smb', TaskQueueStatus.waiting), _task('b', 'smb', TaskQueueStatus.running)],
      {
        'a': const ExtractionTaskState(taskId: 'a', progress: 0.1),
        'b': const ExtractionTaskState(taskId: 'b', status: ExtractionStatus.extracting, progress: 0.75),
      },
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.75);
  });

  testWidgets('the FTP browser shows its own queued download, not an SMB one', (t) async {
    await pumpSmb(
      t,
      [_task('a', 'smb', TaskQueueStatus.running), _task('b', 'ftp', TaskQueueStatus.running)],
      {
        'a': const ExtractionTaskState(taskId: 'a', status: ExtractionStatus.extracting, progress: 0.2),
        'b': const ExtractionTaskState(taskId: 'b', status: ExtractionStatus.extracting, progress: 0.6),
      },
      screen: const FtpScreen(),
    );
    expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.6);
  });
}
