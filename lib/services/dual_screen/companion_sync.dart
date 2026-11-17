import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/services/dual_screen/companion_payload.dart';

/// The game card that last took focus (or was opened) on the games screen.
final focusedGameProvider = StateProvider<Game?>((ref) => null);

/// True while a console's game list is mounted.
final gamesScreenActiveProvider = StateProvider<bool>((ref) => false);

/// Decides what the companion shows and sends it: the focused game's details
/// (with its state, so the buttons there are right) while the games screen
/// is up and a game has focus, the Task Manager otherwise. Details wait
/// [debounce] after focus settles; state updates, of the shown game or of the
/// tasks, go out at most every [throttle]; an unchanged payload is not sent
/// again.
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
  bool _dirty = false;
  bool _showingDetails = false;
  String? _last;

  void start() {
    _subscriptions.addAll([
      _container.listen(focusedGameProvider, (_, __) => _chooseMode()),
      _container.listen(gamesScreenActiveProvider, (_, __) => _chooseMode()),
      _container.listen(launchboxVersionProvider, (_, __) => _chooseMode()),
      _container.listen(gameStateManagerProvider, (_, __) => _onStates()),
      _container.listen(favoritesProvider, (_, __) => _onStates()),
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
      _details = Timer(debounce, _emitDetails);
    } else {
      _details?.cancel();
      if (_showingDetails) {
        _showingDetails = false;
        // A new screen: the task list goes out now, not at the window's end.
        _window?.cancel();
        _window = null;
        _dirty = false;
        _onStates();
      }
    }
  }

  void _emitDetails() {
    final game = _container.read(focusedGameProvider);
    if (game == null) return;
    final state = _container.read(gameStateManagerProvider)[game.gameId] ?? GameState(game: game);
    _emit(detailsPayload(game, launchboxVersion: _container.read(launchboxVersionProvider), state: state));
  }

  void _emitTasks() {
    final favorites = _container.read(favoritesProvider);
    _emit(tasksPayload(_container.read(gameStateManagerProvider).values, isFavorite: favorites.isFavorite));
  }

  /// A state changed: what is on the companion goes out again, at most once
  /// a [throttle] window. Details still waiting on their debounce will read
  /// the new state anyway.
  void _onStates() {
    if (_showingDetails && _details?.isActive == true) return;
    if (_window != null) {
      _dirty = true;
      return;
    }
    _showingDetails ? _emitDetails() : _emitTasks();
    _window = Timer(throttle, () {
      _window = null;
      if (_dirty) {
        _dirty = false;
        _onStates();
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
