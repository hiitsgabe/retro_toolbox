import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _modeKey = 'dual_screen_mode';

/// The display the last move asked for, until the app comes up there.
const _movedToKey = 'dual_screen_moved_to';
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

/// A request from the companion screen (see gameActionRequest in
/// companion_payload.dart), numbered so the same request twice still notifies.
class CompanionRequest {
  const CompanionRequest(this.seq, this.json);

  final int seq;
  final Map<String, dynamic> json;
}

/// The companion's last request. CompanionActionListener runs it: that needs a
/// WidgetRef and a context under the app's Navigator, which this notifier has not.
final companionRequestProvider = StateProvider<CompanionRequest?>((ref) => null);

/// The game with this id is the one the second screen shows: the companion
/// is open and the game has the games screen's focus (or was last tapped).
final shownOnSecondScreenProvider = Provider.family<bool, String>((ref, gameId) =>
    ref.watch(dualScreenProvider.select((s) => s.companionOpen)) && ref.watch(focusedGameProvider.select((g) => g?.gameId == gameId)));

final dualScreenProvider = StateNotifierProvider<DualScreenNotifier, DualScreenState>((ref) => DualScreenNotifier(ref));

/// Puts the app and the companion on the screens the mode asks for, through
/// DualScreenHost on `retro_toolbox/dual_screen`, and feeds the companion while
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
  bool _foreground = true;

  // Every channel job runs after the previous one finishes.
  Future<void> _queue = Future.value();
  Future<void>? _queuedApply;

  Future<void> init() async {
    if (!_enabled) return;
    final saved = (await _prefs()).getString(_modeKey);
    if (!mounted) return;
    state = state.copyWith(mode: DualScreenMode.values.asNameMap()[saved] ?? DualScreenMode.off);
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'displaysChanged':
          // A panel turning on or off can report several changes in a row.
          _displaysChanged?.cancel();
          _displaysChanged = Timer(const Duration(milliseconds: 300), apply);
        case 'companionAction':
          _onCompanionRequest(call.arguments);
      }
    });
    await apply();
  }

  int _requests = 0;

  void _onCompanionRequest(Object? arguments) {
    try {
      final json = jsonDecode(arguments as String) as Map<String, dynamic>;
      _ref.read(companionRequestProvider.notifier).state = CompanionRequest(++_requests, json);
    } catch (e) {
      debugPrint('Dual screen ignored a companion request: $e');
    }
  }

  Future<void> setMode(DualScreenMode mode) async {
    if (!_enabled) return;
    state = state.copyWith(mode: mode);
    final prefs = await _prefs();
    await prefs.setString(_modeKey, mode.name);
    // A choice made by hand gets a fresh move even after one that failed.
    await prefs.remove(_movedToKey);
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
        _foreground = true;
        apply();
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        _foreground = false;
        _displaysChanged?.cancel();
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
      // Nothing opens or moves behind another app's back; resumed applies again.
      if (!_foreground) return await _close();
      final r = await _channel.invokeMapMethod<String, Object?>('displays');
      final current = r?['current'] as int?;
      final displays = [for (final d in (r?['displays'] as List?) ?? const []) DisplayInfo.fromJson(d as Map)];
      if (!mounted) return;
      final hasSecond = displays.any((d) => d.on && d.id != current);
      final plan = planDisplays(state.mode, displays);
      if (plan == null) {
        await _close();
      } else if (current != plan.mainDisplay) {
        // The app restarts on the other display and plans again there. A
        // restart that lands here again would loop for ever, never letting the
        // user reach Settings: the second try gives up.
        final prefs = await _prefs();
        if (prefs.getInt(_movedToKey) == plan.mainDisplay) return await _fail('the move to display ${plan.mainDisplay} did not land');
        await prefs.setInt(_movedToKey, plan.mainDisplay);
        _stopSync();
        await _channel.invokeMethod<void>('moveMain', {'displayId': plan.mainDisplay});
      } else {
        final prefs = await _prefs();
        if (prefs.containsKey(_movedToKey)) await prefs.remove(_movedToKey);
        await _channel.invokeMethod<void>('openCompanion', {'displayId': plan.companionDisplay});
        if (!mounted) return;
        _sync ??= CompanionSync(_ref.container, _send)..start();
      }
      // A run that gets this far clears the last failure.
      if (mounted) state = DualScreenState(mode: state.mode, hasSecondDisplay: hasSecond, companionOpen: _sync != null);
    } catch (e) {
      // PlatformException and MissingPluginException, but a malformed reply too.
      await _fail(e);
    }
  }

  Future<void> _fail(Object e) async {
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
