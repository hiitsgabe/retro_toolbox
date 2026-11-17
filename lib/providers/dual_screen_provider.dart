import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _modeKey = 'dual_screen_mode';
const unavailableMessage = 'Second screen unavailable';

class DualScreenState {
  const DualScreenState({this.mode = DualScreenMode.off, this.hasSecondDisplay = false, this.companionOpen = false, this.error});

  final DualScreenMode mode;

  /// Some display other than the main one is on.
  final bool hasSecondDisplay;
  final bool companionOpen;

  /// The last channel failure, shown in Settings.
  final String? error;

  DualScreenState copyWith({DualScreenMode? mode, bool? hasSecondDisplay, bool? companionOpen, String? error}) => DualScreenState(
        mode: mode ?? this.mode,
        hasSecondDisplay: hasSecondDisplay ?? this.hasSecondDisplay,
        companionOpen: companionOpen ?? this.companionOpen,
        error: error ?? this.error,
      );
}

final dualScreenProvider = StateNotifierProvider<DualScreenNotifier, DualScreenState>((ref) => DualScreenNotifier(ref));

/// Puts the app and the companion on the screens the mode asks for, through
/// MainActivity on `retro_toolbox/dual_screen`, and feeds the companion while
/// it is open. Inert anywhere but Android.
class DualScreenNotifier extends StateNotifier<DualScreenState> {
  DualScreenNotifier(this._ref, {MethodChannel? channel, bool? enabled, Future<SharedPreferences> Function()? prefs})
      : _channel = channel ?? const MethodChannel('retro_toolbox/dual_screen'),
        _enabled = enabled ?? Platform.isAndroid,
        _prefs = prefs ?? SharedPreferences.getInstance,
        super(const DualScreenState());

  final Ref _ref;
  final MethodChannel _channel;
  final bool _enabled;
  final Future<SharedPreferences> Function() _prefs;

  CompanionSync? _sync;
  Timer? _displaysChanged;

  // Every channel job runs after the previous one finishes.
  Future<void> _queue = Future.value();
  Future<void>? _queuedApply;

  Future<void> init() async {
    if (!_enabled) return;
    final saved = (await _prefs()).getString(_modeKey);
    if (!mounted) return;
    state = state.copyWith(mode: DualScreenMode.values.asNameMap()[saved] ?? DualScreenMode.off);
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'displaysChanged') return;
      // A panel turning on or off can report several changes in a row.
      _displaysChanged?.cancel();
      _displaysChanged = Timer(const Duration(milliseconds: 300), apply);
    });
    await apply();
  }

  Future<void> setMode(DualScreenMode mode) async {
    if (!_enabled) return;
    state = state.copyWith(mode: mode);
    await (await _prefs()).setString(_modeKey, mode.name);
    await apply();
  }

  /// Reads the displays and acts on the plan. One already waiting to run
  /// covers this call too; one already running gets a run after it.
  Future<void> apply() {
    if (!_enabled) return Future.value();
    return _queuedApply ??= _enqueue(() {
      _queuedApply = null;
      return _applyNow();
    });
  }

  void onLifecycle(AppLifecycleState s) {
    if (!_enabled) return;
    switch (s) {
      case AppLifecycleState.resumed:
        apply();
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        _enqueue(_close);
      // Launching the companion makes the main activity briefly inactive.
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// The returned future never fails: a job's error is logged and the queue
  /// goes on.
  Future<void> _enqueue(Future<void> Function() job) =>
      _queue = _queue.then((_) => mounted ? job() : null).catchError((Object e) => debugPrint('Dual screen: $e'));

  Future<void> _applyNow() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('displays');
      final current = r?['current'] as int?;
      final displays = [for (final d in (r?['displays'] as List?) ?? const []) DisplayInfo.fromJson(d as Map)];
      if (!mounted) return;
      final hasSecond = displays.any((d) => d.on && d.id != current);
      final plan = planDisplays(state.mode, displays);
      if (plan == null) {
        await _close();
      } else if (current != plan.mainDisplay) {
        // The app restarts on the other display and plans again there.
        _stopSync();
        await _channel.invokeMethod<void>('moveMain', {'displayId': plan.mainDisplay});
      } else {
        await _channel.invokeMethod<void>('openCompanion', {'displayId': plan.companionDisplay});
        if (!mounted) return;
        _sync ??= CompanionSync(_ref.container, _send)..start();
      }
      // A run that gets this far clears the last failure.
      if (mounted) state = DualScreenState(mode: state.mode, hasSecondDisplay: hasSecond, companionOpen: _sync != null);
    } on PlatformException catch (e) {
      await _fail(e);
    } on MissingPluginException catch (e) {
      await _fail(e);
    }
  }

  Future<void> _fail(Exception e) async {
    debugPrint('Dual screen: $e');
    try {
      await _close();
    } on Exception catch (e) {
      debugPrint('Dual screen close: $e');
    }
    if (mounted) state = state.copyWith(error: unavailableMessage);
  }

  Future<void> _close() async {
    _stopSync();
    if (mounted) state = state.copyWith(companionOpen: false);
    await _channel.invokeMethod<void>('closeCompanion');
  }

  Future<void> _send(String json) async {
    try {
      await _channel.invokeMethod<void>('send', {'json': json});
    } on Exception catch (e) {
      debugPrint('Dual screen send: $e');
    }
  }

  void _stopSync() {
    _sync?.dispose();
    _sync = null;
  }

  @override
  void dispose() {
    _displaysChanged?.cancel();
    _stopSync();
    if (_enabled) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
