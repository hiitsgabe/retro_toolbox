import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/companion/companion_tasks_view.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/dual_screen/companion_payload.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_view.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';

/// The second screen's app: it only shows what the main app sends it.
class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key, this.home = const CompanionScreen()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retro Toolbox',
      theme: appTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    );
  }
}

/// The focused game's details, or the Task Manager, as the main app's
/// payloads say (see companion_payload.dart). Touch scrolls and opens images;
/// the buttons send their press to the main app, which runs it as if pressed
/// there and sends the new state back.
class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key, this.channel, this.lookup, this.invalidate});

  /// Null: `retro_toolbox/companion`.
  final MethodChannel? channel;

  /// Null: [LaunchboxService.lookup], which reads the imported files itself.
  final Future<LaunchboxGame?> Function(String platform, int id)? lookup;

  /// Null: [LaunchboxService.invalidate].
  final VoidCallback? invalidate;

  /// Test seam: images without the network or the image cache plugin.
  @visibleForTesting
  static DetailsImageBuilder? debugImageBuilder;

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  late final MethodChannel _channel = widget.channel ?? const MethodChannel('retro_toolbox/companion');

  /// Null with [_tasks] showing.
  Game? _game;
  LaunchboxGame? _launchbox;
  bool _lookingUp = false;
  GameState? _state;
  List<List<CompanionTask>> _taskTabs = [for (final _ in taskTabs) const <CompanionTask>[]];

  /// The LaunchBox import the last details came from (see detailsPayload).
  String? _launchboxVersion;

  /// Counts payloads: a lookup answers only the one it was started for.
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onCall);
    // Native replays the last payload once the handler is in.
    _channel.invokeMethod<void>('ready').catchError((Object e) => debugPrint('Companion ready failed: $e'));
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'update') return;
    try {
      final payload = jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (payload['mode']) {
        case 'details':
          final game = Game.fromJson(payload['game'] as Map<String, dynamic>);
          final state = payload['state'] as Map<String, dynamic>?;
          _state = state == null ? null : gameStateFromJson(state);
          final version = payload['launchbox'] as String?;
          final reimported = version != _launchboxVersion;
          if (reimported) {
            // Another import, or metadata turned off: what this engine
            // decoded is from before.
            _launchboxVersion = version;
            (widget.invalidate ?? LaunchboxService.instance.invalidate)();
          }
          _showGame(game, reimported: reimported);
        case 'tasks':
          final tabs = companionTaskTabs(payload);
          _shown++;
          setState(() {
            _game = null;
            _taskTabs = tabs;
          });
      }
    } catch (e) {
      // A bad payload must not blank the screen: keep what is there.
      debugPrint('Companion ignored a payload: $e');
    }
  }

  void _request(Map<String, dynamic> request) {
    _channel.invokeMethod<void>('action', jsonEncode(request)).catchError((Object e) => debugPrint('Companion request failed: $e'));
  }

  void _showGame(Game game, {bool reimported = false}) {
    final payload = ++_shown;
    final same = game.gameId == _game?.gameId && !reimported;
    final platform = game.details?.launchboxPlatform;
    final id = game.details?.launchboxId;
    final lookUp = platform != null && id != null && !(same && _launchbox != null);
    setState(() {
      _game = game;
      if (!same) _launchbox = null;
      _lookingUp = lookUp;
    });
    if (!lookUp) return;
    (widget.lookup ?? LaunchboxService.instance.lookup)(platform, id).then((lb) {
      if (!mounted || payload != _shown) return;
      setState(() {
        if (lb != null) _launchbox = lb;
        _lookingUp = false;
      });
    }, onError: (Object e) {
      debugPrint('Companion LaunchBox lookup failed: $e');
      if (mounted && payload == _shown) setState(() => _lookingUp = false);
    });
  }

  /// The page's status line, as GameDetailsPage shows it.
  Widget? _status(BuildContext context, GameState? state) {
    if (state == null) return null;
    final error = state.errorMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(state.statusText),
        if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }

  /// The page's action buttons (not favourites or selection, which belong to
  /// the list on the main screen).
  List<Widget>? _actions(Game game, GameState? state) {
    if (state == null) return null;
    final actions = [
      for (final a in state.availableActions)
        if (gameActionLabels.containsKey(a)) a,
    ];
    return [
      for (final a in actions)
        a == actions.first
            ? FilledButton.icon(
                onPressed: () => _request(gameActionRequest(game.gameId, a)),
                icon: Icon(gameActionIcons[a]),
                label: Text(gameActionLabels[a]!),
              )
            : FilledButton.tonalIcon(
                onPressed: () => _request(gameActionRequest(game.gameId, a)),
                icon: Icon(gameActionIcons[a]),
                label: Text(gameActionLabels[a]!),
              ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        // A new key per game: a new scroll position, so it opens at the top.
        child: game == null
            ? CompanionTasksView(key: const ValueKey('tasks'), tabs: _taskTabs, onRequest: _request)
            : GameDetailsView(
                key: ValueKey(game.gameId),
                game: game,
                launchbox: _launchbox,
                launchboxPending: _lookingUp,
                imageBuilder: CompanionScreen.debugImageBuilder,
                onOpenImage: (url) => showImageViewer(context, url),
                status: _status(context, _state),
                actions: _actions(game, _state),
              ),
      ),
    );
  }
}
