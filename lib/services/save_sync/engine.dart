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
      NeedsRoot(:final reason) => 'needs root: $reason',
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
        var base = state.base(hub.key, r.id, key);
        if (base == null) {
          // hub.json may have been replaced while the gens stayed: a base this hub still lists carries over.
          base = state.baseUnderOtherHubId(hub.backend.id, r.id, key, {for (final g in gens) g.gen});
          if (base != null) await state.setBase(hub.key, r.id, key, base);
        }
        var plan = planUnit(unit: key, local: l?.hashes ?? const {}, busy: l?.busy ?? false, base: base, gens: gens);
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

  /// Files this device's current save into the hub as its one backup for the
  /// unit, replacing whatever was there. Never a generation: a generation is
  /// a head, and a backup that became a head would read as a push from this
  /// device and put every other one into divergence.
  ///
  /// A backup that cannot be written does not stop the pull: the pull is what
  /// the owner asked for, the local history still holds a copy, and saying so
  /// is better than refusing.
  Future<String?> _backUp(Recipe r, Binding binding, LocalUnit? local, {required String unitKey}) async {
    if (local == null || local.files.isEmpty) return null;
    try {
      final meta = await Pusher(fs: fsFor(r), hub: hub, stagingRoot: _staging, deviceId: deviceId, deviceName: deviceName, clock: _clock)
          .pack(recipe: r, binding: binding, locationDir: binding.dir(paths), unit: local, kind: 'backup');
      await hub.putBackup(meta.$1, meta.$2, deviceId: deviceId);
      await _log(r.id, unitKey, 'backup', meta.$1.gen, 'ok');
      return null;
    } catch (e) {
      await _log(r.id, unitKey, 'backup', '-', '$e');
      return '$unitKey: the save here could not be backed up to the hub ($e)';
    }
  }

  /// Puts a backup back, from this device's own copy or another handheld's.
  Future<List<String>> restoreBackup(Recipe r, String unitKey, {required String fromDevice, String source = 'bundled'}) => _serial(() async {
        final s = await _status(r, source);
        final binding = s.binding;
        if (binding == null) return ['${r.name}: ${bindLabel(s.bind)}'];
        final meta = await hub.backup(fromDevice, r.id, unitKey);
        if (meta == null) return ['$unitKey: there is no backup from that device'];
        try {
          await _puller(fsFor(r)).pull(
            recipe: r,
            binding: binding,
            locationDir: binding.dir(paths),
            unitKey: unitKey,
            gen: meta,
            expectedLocal: s.units[unitKey]?.local?.hashes ?? const {},
            payload: await hub.backupPayload(fromDevice, r.id, unitKey),
          );
          await _log(r.id, unitKey, 'restore', meta.gen, 'ok');
          return ['$unitKey: restored from ${meta.deviceName}'];
        } catch (e) {
          await _log(r.id, unitKey, 'restore', meta.gen, '$e');
          return ['$unitKey: $e'];
        }
      });

  /// Settles a unit both sides changed, by keeping one version. [keep] is
  /// [keepLocal] or the id of a head in the hub.
  ///
  /// Nothing is thrown away: keeping the hub's copy pulls it, which files the
  /// replaced save into this device's history first, and either way the
  /// result is pushed as one generation naming every head as a parent. That
  /// single descendant is what ends the divergence — for this device and for
  /// every other one, without any of them being asked the question again.
  static const keepLocal = 'local';

  Future<List<String>> resolve(Recipe r, String unitKey, {required String keep, String source = 'bundled'}) => _serial(() async {
        final s = await _status(r, source);
        final binding = s.binding;
        if (binding == null) return ['${r.name}: ${bindLabel(s.bind)}'];
        if (s.error != null) return ['${r.name}: ${s.error}'];
        final plan = s.units[unitKey]?.plan;
        if (plan is! Diverged) return ['$unitKey: nothing to settle'];
        final heads = plan.heads;
        try {
          if (keep != keepLocal) {
            final chosen = heads.where((h) => h.gen == keep).firstOrNull;
            if (chosen == null) return ['$unitKey: that version is no longer in the hub; refresh and try again'];
            await _puller(fsFor(r)).pull(
              recipe: r,
              binding: binding,
              locationDir: binding.dir(paths),
              unitKey: unitKey,
              gen: chosen,
              expectedLocal: s.units[unitKey]?.local?.hashes ?? const {},
            );
            await _log(r.id, unitKey, 'resolve-pull', chosen.gen, 'ok');
          }
          // Re-read: keeping the hub's copy has just changed what is here.
          final after = await _status(r, source);
          final local = after.units[unitKey]?.local;
          if (local == null) return ['$unitKey: nothing to push'];
          final gen = await Pusher(fs: fsFor(r), hub: hub, stagingRoot: _staging, deviceId: deviceId, deviceName: deviceName, clock: _clock)
              .push(recipe: r, binding: binding, locationDir: binding.dir(paths), unit: local, parents: heads, kind: 'merge');
          await state.setBase(hub.key, r.id, unitKey, Base(gen.gen, gen.hashes));
          await hub.prune(r.id, unitKey, deviceId: deviceId, now: _clock());
          await state.setLast(r.id, 'push', _clock());
          await _log(r.id, unitKey, 'resolve', gen.gen, 'ok');
          return ['$unitKey: settled'];
        } catch (e) {
          await _log(r.id, unitKey, 'resolve', '-', '$e');
          return ['$unitKey: $e'];
        }
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
            // The save about to be replaced goes to the hub first, as this
            // device's one backup. The local history already keeps copies,
            // but it keeps them on the handheld that is about to be
            // overwritten — no use at all if that is the thing that failed.
            final warn = await _backUp(r, binding, u.local, unitKey: plan.unit);
            if (warn != null) out.add(warn);
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
