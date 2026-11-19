import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rar/rar.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/archive_extract_service.dart';
import 'package:retro_toolbox/services/python_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Directory root;

String at(String rel) => p.join(root.path, rel);

File touch(String rel, [String body = 'x']) => File(at(rel))
  ..createSync(recursive: true)
  ..writeAsStringSync(body);

/// Stands in for the embedded Python worker: answers this test's jobs, DONE
/// for any input but one named bad.*, which reports an error.
Timer fakeWorker(String jobsDir) => Timer.periodic(const Duration(milliseconds: 50), (_) {
      for (final f in Directory(jobsDir).listSync().whereType<File>()) {
        if (!p.basename(f.path).startsWith('job_')) continue;
        final Map<String, dynamic> job;
        try {
          job = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {
          continue; // still being written
        }
        final input = (job['nsz_file'] ?? job['input_file']) as String?;
        if (input == null || !p.isWithin(root.path, input)) continue; // another test process's job
        f.deleteSync();
        final bad = p.basenameWithoutExtension(input) == 'bad';
        if (!bad) touch(p.join(p.relative(job['output_dir'] as String, from: root.path), '${p.basenameWithoutExtension(input)}.out'));
        File(job['progress_file'] as String).writeAsStringSync(bad ? 'ERROR:corrupt\n' : 'DONE\n');
      }
    });

class _FakeRar extends RarPlatform {
  final extracted = <String>[];
  @override
  Future<Map<String, dynamic>> extractRarFile({required String rarFilePath, required String destinationPath, String? password}) async {
    extracted.add(rarFilePath);
    if (p.basename(rarFilePath).startsWith('bad')) return {'success': false, 'message': 'corrupt'};
    File(p.join(destinationPath, 'game.iso'))
      ..createSync(recursive: true)
      ..writeAsStringSync('iso');
    return {'success': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Timer? worker;
  final savedRar = RarPlatform.instance;

  setUpAll(() {
    PythonWorker.launch = (env) async {
      worker = fakeWorker(env['JOBS_DIR']!);
      return null;
    };
  });
  tearDownAll(() => worker?.cancel());

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('delete_originals');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => root.path);
  });
  tearDown(() {
    RarPlatform.instance = savedRar;
    ArchiveExtractService.linuxRar = null;
    root.deleteSync(recursive: true);
  });

  /// Queues one task the way the tool screens do and waits (in real time) until
  /// it has finished; returns its final queue status.
  Future<TaskQueueStatus> run(TaskType type, Map<String, dynamic> params) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(taskQueueProvider.notifier).enqueue('t', type, {'taskId': 't', ...params});
    TaskQueueStatus status() => c.read(taskQueueProvider).tasks.single.status;
    for (var i = 0; i < 500 && (status() == TaskQueueStatus.waiting || status() == TaskQueueStatus.running); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return status();
  }

  Map<String, dynamic> nsz(String input, Object? delete) => {
        'nszFilePath': input,
        'outputDir': root.path,
        'keysPath': at('prod.keys'),
        if (delete != null) 'deleteOriginals': delete,
      };

  Map<String, dynamic> cia(String input, Object? delete) => {
        'inputPath': input,
        'outputDir': root.path,
        if (delete != null) 'deleteOriginals': delete,
      };

  Map<String, dynamic> archive(String input, Object? delete) => {
        'archivePath': input,
        'outputDir': at('out'),
        if (delete != null) 'deleteOriginals': delete,
      };

  group('NSZ decompress', () {
    test('success with deleteOriginals deletes the .nsz', () async {
      final input = touch('game.nsz');
      expect(await run(TaskType.nszDecompression, nsz(input.path, true)), TaskQueueStatus.completed);
      expect(File(at('game.out')).existsSync(), isTrue);
      expect(input.existsSync(), isFalse);
    });

    test('success without it keeps the .nsz, and a missing param means keep', () async {
      final kept = touch('game.nsz');
      expect(await run(TaskType.nszDecompression, nsz(kept.path, false)), TaskQueueStatus.completed);
      expect(kept.existsSync(), isTrue);

      final old = touch('old.nsz'); // a task queued before the option existed
      expect(await run(TaskType.nszDecompression, nsz(old.path, null)), TaskQueueStatus.completed);
      expect(old.existsSync(), isTrue);
    });

    test('a failure keeps the .nsz even with deleteOriginals', () async {
      final input = touch('bad.nsz');
      expect(await run(TaskType.nszDecompression, nsz(input.path, true)), TaskQueueStatus.failed);
      expect(input.existsSync(), isTrue);
    });
  });

  group('3DS to CIA', () {
    test('success with deleteOriginals deletes the .3ds', () async {
      final input = touch('game.3ds');
      expect(await run(TaskType.cia3dsConversion, cia(input.path, true)), TaskQueueStatus.completed);
      expect(File(at('game.out')).existsSync(), isTrue);
      expect(input.existsSync(), isFalse);
    });

    test('success without it keeps the .3ds, and a missing param means keep', () async {
      final kept = touch('game.3ds');
      expect(await run(TaskType.cia3dsConversion, cia(kept.path, false)), TaskQueueStatus.completed);
      expect(kept.existsSync(), isTrue);

      final old = touch('old.3ds');
      expect(await run(TaskType.cia3dsConversion, cia(old.path, null)), TaskQueueStatus.completed);
      expect(old.existsSync(), isTrue);
    });

    test('a failure keeps the .3ds even with deleteOriginals', () async {
      final input = touch('bad.3ds');
      expect(await run(TaskType.cia3dsConversion, cia(input.path, true)), TaskQueueStatus.failed);
      expect(input.existsSync(), isTrue);
    });
  });

  group('archive extraction', () {
    File zip(String rel) {
      final f = File(at(rel))..createSync(recursive: true);
      final a = Archive()..addFile(ArchiveFile.string('game.iso', 'iso'));
      f.writeAsBytesSync(ZipEncoder().encode(a));
      return f;
    }

    test('a zip with deleteOriginals is deleted after it unpacks', () async {
      final input = zip('game.zip');
      expect(await run(TaskType.archiveExtraction, archive(input.path, true)), TaskQueueStatus.completed);
      expect(File(at('out/game.iso')).readAsStringSync(), 'iso');
      expect(input.existsSync(), isFalse);
    });

    test('a zip without it is kept, and a missing param means keep', () async {
      final kept = zip('game.zip');
      expect(await run(TaskType.archiveExtraction, archive(kept.path, false)), TaskQueueStatus.completed);
      expect(kept.existsSync(), isTrue);

      final old = zip('old.zip');
      expect(await run(TaskType.archiveExtraction, {...archive(old.path, null), 'outputDir': at('old')}), TaskQueueStatus.completed);
      expect(old.existsSync(), isTrue);
    });

    test('a failed extraction keeps the zip even with deleteOriginals', () async {
      final input = zip('game.zip');
      touch('out'); // a file where the output folder goes: nothing can be written
      expect(await run(TaskType.archiveExtraction, archive(input.path, true)), TaskQueueStatus.failed);
      expect(input.existsSync(), isTrue);
    });

    test('a multi-part rar with deleteOriginals deletes every part, and nothing else', () async {
      RarPlatform.instance = _FakeRar();
      ArchiveExtractService.linuxRar = true;
      final parts = [touch('game.part1.rar'), touch('game.part2.rar'), touch('game.part3.rar')];
      final others = [touch('other.part1.rar'), touch('game.nfo'), touch('game.rar')];
      expect(await run(TaskType.archiveExtraction, archive(parts.first.path, true)), TaskQueueStatus.completed);
      expect(File(at('out/game.iso')).existsSync(), isTrue);
      expect([for (final f in parts) f.existsSync()], [false, false, false]);
      expect([for (final f in others) f.existsSync()], [true, true, true]);
    });

    test('an old-style rar set (.rar, .r00, .r01) goes whole', () async {
      RarPlatform.instance = _FakeRar();
      ArchiveExtractService.linuxRar = true;
      final parts = [touch('Game.rar'), touch('Game.r00'), touch('Game.r01')];
      final other = touch('Game.nfo');
      expect(await run(TaskType.archiveExtraction, archive(parts.first.path, true)), TaskQueueStatus.completed);
      expect([for (final f in parts) f.existsSync()], [false, false, false]);
      expect(other.existsSync(), isTrue);
    });

    test('a failed multi-part rar keeps every part', () async {
      RarPlatform.instance = _FakeRar();
      ArchiveExtractService.linuxRar = true;
      final parts = [touch('bad.part1.rar'), touch('bad.part2.rar')];
      expect(await run(TaskType.archiveExtraction, archive(parts.first.path, true)), TaskQueueStatus.failed);
      expect([for (final f in parts) f.existsSync()], [true, true]);
    });
  });

  group('ArchiveExtractService.volumes', () {
    test('a plain archive is only itself', () {
      final zip = touch('game.zip');
      touch('game.z01');
      expect(ArchiveExtractService.volumes(zip.path), [zip.path]);
    });

    test('a partN.rar set, whichever part is picked, in part order', () {
      final parts = [
        for (final n in ['01', '02', '10']) touch('Game.Part$n.rar').path
      ];
      touch('Game Two.part01.rar');
      expect(ArchiveExtractService.volumes(parts[1]), parts);
    });

    test('a .rar with .rNN volumes', () {
      final main = touch('game.rar').path;
      final vols = [touch('game.r00').path, touch('game.R01').path];
      touch('game.r00.bak');
      touch('gamex.r00');
      expect(ArchiveExtractService.volumes(main), [main, ...vols]);
    });
  });
}
