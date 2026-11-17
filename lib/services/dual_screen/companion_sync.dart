import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/services/dual_screen/companion_payload.dart';

/// The game card that last took focus (or was opened) on the games screen.
final focusedGameProvider = StateProvider<Game?>((ref) => null);

/// True while a console's game list is mounted.
final gamesScreenActiveProvider = StateProvider<bool>((ref) => false);

/// Decides what the companion shows and sends it: the focused game's details
/// while the games screen is up and a game has focus, the Task Manager
/// otherwise. Details wait [debounce] after focus settles; task updates go
/// out at most every [throttle]; an unchanged payload is not sent again.
class CompanionSync {
  CompanionSync(
    this._container,
    this._send, {
    this.debounce = const Duration(milliseconds: 150),
    this.throttle = const Duration(milliseconds: 500),
  });

  final ProviderContainer _container;
  final Future<void> Function(String json) _send;
  final Duration debounce;
  final Duration throttle;

  final _subscriptions = <ProviderSubscription<Object?>>[];
  Timer? _details;
  Timer? _window;
  bool _tasksDirty = false;
  bool _showingDetails = false;
  String? _last;

  void start() {
    _subscriptions.addAll([
      _container.listen(focusedGameProvider, (_, __) => _chooseMode()),
      _container.listen(gamesScreenActiveProvider, (_, __) => _chooseMode()),
      _container.listen(launchboxVersionProvider, (_, __) => _chooseMode()),
      _container.listen(gameStateManagerProvider, (_, __) => _onTasks()),
    ]);
    // Nothing is on the companion yet, so the task list must go out too.
    _showingDetails = true;
    _chooseMode();
  }

  void dispose() {
    for (final s in _subscriptions) {
      s.close();
    }
    _subscriptions.clear();
    _details?.cancel();
    _window?.cancel();
  }

  bool get _wantsDetails => _container.read(gamesScreenActiveProvider) && _container.read(focusedGameProvider) != null;

  void _chooseMode() {
    if (_wantsDetails) {
      _showingDetails = true;
      _details?.cancel();
      _details = Timer(debounce, () {
        final game = _container.read(focusedGameProvider);
        if (game != null) _emit(detailsPayload(game, launchboxVersion: _container.read(launchboxVersionProvider)));
      });
    } else {
      _details?.cancel();
      if (_showingDetails) {
        _showingDetails = false;
        // A new screen: the task list goes out now, not at the window's end.
        _window?.cancel();
        _window = null;
        _tasksDirty = false;
        _onTasks();
      }
    }
  }

  void _onTasks() {
    if (_showingDetails) return;
    if (_window != null) {
      _tasksDirty = true;
      return;
    }
    _emit(tasksPayload(_container.read(gameStateManagerProvider).values));
    _window = Timer(throttle, () {
      _window = null;
      if (_tasksDirty) {
        _tasksDirty = false;
        _onTasks();
      }
    });
  }

  void _emit(Map<String, dynamic> payload) {
    final json = jsonEncode(payload);
    if (json == _last) return;
    _last = json;
    unawaited(_send(json));
  }
}
