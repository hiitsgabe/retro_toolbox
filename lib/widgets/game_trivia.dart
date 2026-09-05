import 'package:flutter/material.dart';
import 'package:roms_downloader/widgets/common/hammer_loader.dart';

/// Rotating game-trivia loader: the swinging hammer, a big quoted curiosity that
/// changes every few seconds, and the real status line small and dim
/// underneath. Optionally shows a progress bar (for patching). Makes long waits
/// feel alive.
class GameTriviaLoader extends StatefulWidget {
  /// The real progress/status text (e.g. "Loading squads 40%").
  final String? status;

  /// 0..1 progress bar under the status, or null to omit it.
  final double? progress;

  /// Seed to pick the first trivia (so it varies per open without randomness).
  final int seed;
  const GameTriviaLoader({super.key, this.status, this.progress, this.seed = 0});

  @override
  State<GameTriviaLoader> createState() => _GameTriviaLoaderState();
}

class _GameTriviaLoaderState extends State<GameTriviaLoader> {
  late int _i = widget.seed % _trivia.length;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  // Advance every 30s via chained post-frame delays (no Timer import needed and
  // cancels cleanly when unmounted).
  void _tick() {
    Future.delayed(const Duration(seconds: 30), () {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _trivia.length);
      _tick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const HammerLoader(),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Padding(
                key: ValueKey(_i),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '"${_trivia[_i]}"',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.35),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.status ?? 'Working…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            if (widget.progress != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: 240,
                child: LinearProgressIndicator(
                  value: widget.progress == 0 ? null : widget.progress,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Generic gaming curiosities — no specific game titles (kept brand-neutral).
const List<String> _trivia = [
  'The term "Easter egg" for a hidden feature was coined in the early days of home consoles.',
  'The first video games ran on machines that filled entire university rooms.',
  'Sprite flickering on old consoles happened because the hardware could only draw so many objects per scanline.',
  'Early cartridges used battery-backed memory to save games, and those batteries eventually die.',
  'Blowing into cartridges never actually fixed them; reseating the contacts did.',
  'The "konami code" up-up-down-down became one of gaming\'s most famous cheat inputs.',
  'Arcade high-score tables often limited names to three letters to save memory.',
  'The frame rate of a game is how many still images it shows you every second.',
  'Many classic games ran faster in North America than Europe because of different TV standards.',
  'Pixel art exists because early screens and memory could only afford a handful of colors.',
  'Chiptune music was written to fit in just a few kilobytes of sound hardware.',
  'The D-pad was invented to give players precise control with a single thumb.',
  'A "ROM" is a read-only copy of a game cartridge or disc.',
  'Save states let emulators freeze a game at any exact moment.',
  'Region locking stopped games from one country running on consoles from another.',
  'Some cartridges held extra chips that made the console more powerful than it shipped.',
  'The loading times of disc consoles were a trade for far more storage than cartridges.',
  'CRT televisions blended pixels in a way that modern sharp screens do not.',
  'Speedrunners exploit tiny glitches to finish games in a fraction of the intended time.',
  'The first handheld consoles used interchangeable cartridges just like their big siblings.',
  'Many beloved soundtracks were composed under severe memory limits, forcing clever tricks.',
  'A "port" is a version of a game rebuilt to run on different hardware.',
  'Anti-piracy screens sometimes hid in games and only triggered on copied cartridges.',
  'Two-player games often shared one screen because splitting it cost precious performance.',
  'Light-gun games only worked on CRTs because they read the screen\'s electron beam.',
  'The health bar was a simple way to show damage without complex numbers on screen.',
  'Some racing games faked 3D with clever 2D scaling long before real 3D hardware.',
  'A "boss" enemy was originally just a bigger sprite with more hit points.',
  'Passwords let you resume long games before battery saves were common.',
  'The pause feature was a genuine innovation early arcade games did not have.',
  'Cartridge slots had dust covers because dirty contacts caused most "broken" games.',
  'Many franchises started as arcade machines before coming home.',
  'The score attack loop kept arcades profitable one quarter at a time.',
  'Rumble feedback added a sense of touch decades after games first had sound.',
  'Analog sticks brought fine, 360-degree control that a D-pad could not.',
  'Memory cards let you carry your saved games to a friend\'s console.',
  'Some games shipped with maps and manuals because the cartridge had no room to explain.',
  'The "continue" screen was often a last chance to feed the arcade machine more coins.',
  'Backwards compatibility lets a newer console play an older one\'s games.',
  'Emulation preserves games whose original hardware is decades out of production.',
];
