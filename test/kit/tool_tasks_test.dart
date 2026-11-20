import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

QueuedTask _task(String id, TaskQueueStatus status, {TaskType type = TaskType.chdConversion, String? error}) =>
    QueuedTask(id: id, type: type, status: status, params: {'inputPath': '/roms/$id.cue', 'outputDir': '/roms'}, createdAt: DateTime(2026), error: error);

StatusPanel _status(List<QueuedTask> tasks, {Map<String, double> progress = const {}}) => toolTaskStatus(
      TaskQueueState(tasks: tasks),
      ExtractionState(tasks: {for (final e in progress.entries) e.key: ExtractionTaskState(taskId: e.key, status: ExtractionStatus.extracting, progress: e.value)}),
      TaskType.chdConversion,
      name: (t) => '${t.id}.cue',
      saved: (t) => 'Saved ${t.id}.chd',
    );

void main() {
  test('nothing of this tool in the task list: hidden', () {
    final s = _status([_task('mgs', TaskQueueStatus.running, type: TaskType.nszDecompression)]);
    expect(s.kind, StatusKind.hidden);
    expect(_status(const []).kind, StatusKind.hidden);
  });

  test('running and waiting tasks are the work: progress from the extraction, the rest queued', () {
    final s = _status([_task('ff1', TaskQueueStatus.completed), _task('ff2', TaskQueueStatus.running), _task('ff3', TaskQueueStatus.waiting)], progress: {'ff2': 0.4});
    expect(s.kind, StatusKind.working);
    expect([for (final i in s.items) (i.name, i.state, i.progress)], [
      ('ff1.cue', WorkState.done, null),
      ('ff2.cue', WorkState.running, 0.4),
      ('ff3.cue', WorkState.queued, null),
    ]);
  });

  test('a waiting task alone is work too: queued', () {
    final s = _status([_task('ff1', TaskQueueStatus.waiting)]);
    expect(s.kind, StatusKind.working);
    expect(s.items.single.state, WorkState.queued);
  });

  test('a running task with no progress yet has an unknown bar', () {
    final s = _status([_task('ff1', TaskQueueStatus.running)]);
    expect(s.items.single.progress, isNull);
  });

  test('only the newest finished tasks stay beside the work', () {
    final s = _status([for (var i = 0; i < 6; i++) _task('d$i', TaskQueueStatus.completed), _task('run', TaskQueueStatus.running)]);
    expect(s.items.map((i) => i.name), ['d3.cue', 'd4.cue', 'd5.cue', 'run.cue']);
  });

  test('all done: the newest result names what was saved and counts the rest', () {
    expect(_status([_task('ff1', TaskQueueStatus.completed)]).text, 'Saved ff1.chd');
    final s = _status([_task('ff1', TaskQueueStatus.completed), _task('ff2', TaskQueueStatus.completed)]);
    expect(s.kind, StatusKind.done);
    expect(s.text, 'Saved ff2.chd, and 1 more');
    expect(s.problems, isEmpty);
  });

  test('one failure alone is an error: one line, the raw error behind Details', () {
    final s = _status([_task('crash', TaskQueueStatus.failed, error: 'Error: file not found: track 2')]);
    expect(s.kind, StatusKind.error);
    expect(s.text, 'Could not convert crash.cue');
    expect(s.detail, 'Error: file not found: track 2');
  });

  test('several failures alone: one line counts them, Details lists each', () {
    final s = _status([_task('a', TaskQueueStatus.failed, error: 'boom'), _task('b', TaskQueueStatus.failed, error: 'bang')]);
    expect(s.kind, StatusKind.error);
    expect(s.text, 'Could not convert 2 files');
    expect(s.detail, 'a.cue: boom\nb.cue: bang');
  });

  test('done with failures lists them with the reason; a cancel is skipped', () {
    final s = _status([
      _task('ok', TaskQueueStatus.completed),
      _task('bad', TaskQueueStatus.failed, error: 'chdman exited 1\nlong trace'),
      _task('gone', TaskQueueStatus.cancelled),
    ]);
    expect(s.kind, StatusKind.done);
    expect(s.text, 'Saved ok.chd');
    expect([for (final p in s.problems) (p.name, p.reason, p.failed)], [('bad.cue', 'chdman exited 1', true), ('gone.cue', 'Cancelled', false)]);
  });

  test('where narrows a shared type to this screen\'s tasks; action offers a step for the newest result', () {
    final tasks = [
      QueuedTask(id: 'a', type: TaskType.remoteTransfer, status: TaskQueueStatus.completed, params: {'source': 'link', 'label': 'a.zip'}, createdAt: DateTime(2026)),
      QueuedTask(id: 'b', type: TaskType.remoteTransfer, status: TaskQueueStatus.running, params: {'source': 'explorer', 'label': 'b.bin'}, createdAt: DateTime(2026)),
    ];
    final s = toolTaskStatus(
      TaskQueueState(tasks: tasks),
      const ExtractionState(),
      TaskType.remoteTransfer,
      name: (t) => '${t.params['label']}',
      saved: (t) => 'Saved ${t.params['label']}',
      where: (t) => t.params['source'] == 'link',
      action: (t) => t.id == 'a' ? ('Extract here', () {}) : null,
    );
    expect(s.kind, StatusKind.done);
    expect(s.text, 'Saved a.zip');
    expect(s.actionLabel, 'Extract here');
    expect(s.onAction, isNotNull);
  });
}
