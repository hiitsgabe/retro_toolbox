import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/errors.dart';
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_report.dart';
import 'package:retro_toolbox/services/save_sync/local_history.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/puller.dart';
import 'package:retro_toolbox/services/save_sync/pusher.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/save_checks.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

class UnitStatus {
  const UnitStatus(this.plan, {this.local, this.newest});

  final UnitPlan plan;
  final LocalUnit? local;

  /// The newest head in the hub, for display.
  final GenMeta? newest;
}

class GameStatus {
  const GameStatus(
    this.recipe,
    this.source,
    this.bind, {
    this.units = const {},
    this.error,
    this.installedVersion,
    this.running = false,
    this.notes = const [],
  });

  final Recipe recipe;

  /// bundled, repo, user or hub.
  final String source;
  final BindResult bind;
  final Map<String, UnitStatus> units;
  final String? error;
  final String? installedVersion;
  final bool running;

  /// What this status did on its own, such as recovering an interrupted pull.
  final List<String> notes;

  Binding? get binding => switch (bind) {
        Bound(:final binding) => binding,
        _ => null,
      };

  bool get backupOnly => binding?.mode == 'backup';
  bool get canPush => units.values.any((u) => u.plan is PushPlan);
  bool get canPull => !backupOnly && units.values.any((u) => u.plan is PullPlan);
}

/// The binding state in words, for the screen and the device report.
String bindLabel(BindResult b) => switch (b) {
      Bound() => 'ready',
      NeedsConfirm() => 'confirm where the saves are',
      NotInstalled() => 'not installed',
      NeedsRoot() => 'needs root',
      FolderMissing() => 'open the game once so it creates its save folder',
      NeedsDiscovery(:final reason) => 'save location unknown ($reason)',
    };

/// One device's sync: status, push, pull, check and the hub reports, one
/// action at a time.
class SaveSyncEngine {
  SaveSyncEngine({
    required this.shell,
    required this.hub,
    required this.state,
    required this.paths,
    required this.deviceId,
    required this.deviceName,
    this.model = '',
    this.appVersion = '',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PrivilegedShell shell;
  final Hub hub;
  final SyncState state;
  final DevicePaths paths;
  final String deviceId;
  final String deviceName;
  final String model;
  final String appVersion;
  final DateTime Function() _clock;

  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  GameFs fsFor(Recipe r) => ShellGameFs(shell, PathGuard([for (final pkg in r.packages) for (final a in Area.values) paths.area(a, pkg), paths.saveSync]));

  String get _staging => p.join(paths.saveSync, '.staging');

  Puller _puller(GameFs fs) => Puller(fs: fs, hub: hub, history: LocalHistory(p.join(paths.saveSync, 'history'), fs), stagingRoot: _staging);

  Future<GameStatus> status(Recipe r, {String source = 'bundled'}) => _serial(() => _status(r, source));

  Future<GameStatus> _status(Recipe r, String source) async {
    final fs = fsFor(r);
    final stored = state.binding(r.id);
    BindResult? bind;
    // Binding probes the save folders too: a probe that fails is this game's error, not a throw that hides every game.
    try {
      if (stored != null) {
        bind = stored.area == Area.internal && shell.privilege != Privilege.root ? NeedsRoot(stored) : Bound(stored);
      } else {
        bind = await RecipeBinder(fs, paths, privilege: shell.privilege).bind(r);
        if (bind is Bound) await state.setBinding(bind.binding);
      }
      final binding = switch (bind) {
        Bound(:final binding) => binding,
        _ => null,
      };
      if (binding == null) return GameStatus(r, source, bind);
      final running = await fs.running(binding.package);
      final notes = <String>[];
      final stuck = <String>{};
      if (!running) {
        final recovered = await _puller(fs).recover(r);
        for (final unit in recovered.recovered) {
          notes.add('Recovered an interrupted pull of $unit');
        }
        for (final s in recovered.stuck) {
          notes.add('${s.unit}: ${s.message}');
          stuck.add(s.unit);
        }
      }
      final installed = await fs.versionName(binding.package);
      final local = await UnitScanner(fs).scan(r, binding.dir(paths));
      final keys = {...local.keys, ...await hub.units(r.id), ...stuck}.toList()..sort();
      final units = <String, UnitStatus>{};
      for (final key in keys) {
        final gens = await hub.gens(r.id, key);
        final l = local[key];
        var plan = planUnit(unit: key, local: l?.hashes ?? const {}, busy: l?.busy ?? false, base: state.base(hub.key, r.id, key), gens: gens);
        if (stuck.contains(key)) {
          // Its files are half pulled: neither a push nor a base may come from them.
          plan = Blocked(key, 'interrupted pull needs attention');
        } else if (!running && plan is UpToDate && plan.adopt != null) {
          await state.setBase(hub.key, r.id, key, Base(plan.adopt!.gen, plan.adopt!.hashes));
        }
        if (running && (plan is PushPlan || plan is PullPlan)) {
          plan = Blocked(key, '${r.name} is running');
        } else if (plan is PullPlan) {
          final refused = versionRefusal(r, plan.gen, installed);
          if (refused != null) plan = Blocked(key, refused);
        }
        final heads = headsOf(gens);
        units[key] = UnitStatus(plan, local: l, newest: heads.isEmpty ? null : heads.first);
      }
      return GameStatus(r, source, bind, units: units, installedVersion: installed, running: running, notes: notes);
    } catch (e) {
      return GameStatus(r, source, bind ?? const NeedsDiscovery('could not look in the save folders'), error: '$e');
    }
  }

  Future<List<String>> push(Recipe r, {String source = 'bundled'}) => _serial(() async {
        final s = await _status(r, source);
        final binding = s.binding;
        if (binding == null) return ['${r.name}: ${bindLabel(s.bind)}'];
        if (s.error != null) return ['${r.name}: ${s.error}'];
        final pusher = Pusher(fs: fsFor(r), hub: hub, stagingRoot: _staging, deviceId: deviceId, deviceName: deviceName, clock: _clock);
        final out = <String>[];
        var pushed = false;
        for (final u in s.units.values) {
          final plan = u.plan;
          if (plan is! PushPlan) continue;
          try {
            final known = {for (final g in await hub.gens(r.id, plan.unit)) g.gen: g};
            final parents = [for (final id in plan.parents) known[id] ?? (throw SyncBlocked('$id is no longer in the hub; refresh and try again'))];
            final gen = await pusher.push(recipe: r, binding: binding, locationDir: binding.dir(paths), unit: u.local!, parents: parents);
            await state.setBase(hub.key, r.id, plan.unit, Base(gen.gen, gen.hashes));
            await hub.prune(r.id, plan.unit, deviceId: deviceId, now: _clock());
            pushed = true;
            out.add('${plan.unit}: pushed');
            await _log(r.id, plan.unit, 'push', gen.gen, 'ok');
          } catch (e) {
            out.add('${plan.unit}: $e');
            await _log(r.id, plan.unit, 'push', '-', '$e');
          }
        }
        if (pushed) {
          await state.setLast(r.id, 'push', _clock());
          if (source != 'hub') await hub.publishRecipe(r.raw, source: source, deviceId: deviceId, now: _clock());
        }
        return out.isEmpty ? ['Nothing to push'] : out;
      });

  Future<List<String>> pull(Recipe r, {String source = 'bundled'}) => _serial(() async {
        final s = await _status(r, source);
        final binding = s.binding;
        if (binding == null) return ['${r.name}: ${bindLabel(s.bind)}'];
        if (s.error != null) return ['${r.name}: ${s.error}'];
        if (s.backupOnly) return ['${r.name} is backup only on this device (the game has its own cloud), so pull is off'];
        final puller = _puller(fsFor(r));
        final out = <String>[];
        var pulled = false;
        for (final u in s.units.values) {
          final plan = u.plan;
          if (plan is! PullPlan) continue;
          try {
            await puller.pull(
              recipe: r,
              binding: binding,
              locationDir: binding.dir(paths),
              unitKey: plan.unit,
              gen: plan.gen,
              expectedLocal: u.local?.hashes ?? const {},
            );
            await state.setBase(hub.key, r.id, plan.unit, Base(plan.gen.gen, plan.gen.hashes));
            pulled = true;
            out.add('${plan.unit}: pulled');
            await _log(r.id, plan.unit, 'pull', plan.gen.gen, 'ok');
          } catch (e) {
            out.add('${plan.unit}: $e');
            await _log(r.id, plan.unit, 'pull', plan.gen.gen, '$e');
          }
        }
        if (pulled) await state.setLast(r.id, 'pull', _clock());
        return out.isEmpty ? ['Nothing to pull'] : out;
      });

  Future<List<CheckLine>> check(Recipe r, {String source = 'bundled'}) => _serial(() => GameChecker(
        fs: fsFor(r),
        hub: hub,
        paths: paths,
        privilege: shell.privilege,
        stagingRoot: _staging,
      ).check(r, source: source, binding: state.binding(r.id)));

  /// Rewrites this device's file in the hub, then README.txt from every device file.
  Future<void> report(List<GameStatus> games, {required String access}) => _serial(() async {
        final now = _clock().toUtc();
        final me = DeviceReport(
          id: deviceId,
          name: deviceName,
          model: model,
          toolboxVersion: appVersion,
          lastSeen: now,
          access: access,
          games: [
            for (final g in games)
              GameReport(
                recipe: g.recipe.id,
                name: g.recipe.name,
                package: g.binding?.package,
                version: g.installedVersion,
                state: bindLabel(g.bind),
                units: [
                  for (final e in g.units.entries)
                    if (e.value.local != null) e.key,
                ],
                lastPush: state.last(g.recipe.id, 'push'),
                lastPull: state.last(g.recipe.id, 'pull'),
              ),
          ],
        );
        await hub.writeDevice(deviceId, me.toJson());
        await hub.writeReadme(buildReadme(
          devices: [for (final j in await hub.devices()) DeviceReport.fromJson(j)],
          gameNames: {for (final g in games) g.recipe.id: g.recipe.name},
          newest: {
            for (final g in games)
              g.recipe.id: {
                for (final e in g.units.entries)
                  if (e.value.newest != null) e.key: e.value.newest!,
              },
          },
          writtenBy: deviceName,
          now: now,
        ));
      });

  Future<void> _log(String recipe, String unit, String action, String gen, String result) async {
    final f = File(p.join(paths.saveSync, 'log.txt'));
    await f.parent.create(recursive: true);
    await f.writeAsString('${_clock().toUtc().toIso8601String()}\t$recipe\t$unit\t$action\t$gen\t${result.replaceAll('\n', ' ')}\n', mode: FileMode.append);
  }
}
