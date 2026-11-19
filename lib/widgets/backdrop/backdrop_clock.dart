/// One clock for every animated backdrop. Each page paints a backdrop of its
/// own, and one starting from zero on every push makes the paint jump the
/// moment a screen opens; started where the process clock is, they all agree.
final _since = Stopwatch()..start();

/// Where a loop of [period] is now, from 0 to 1.
double backdropPhase(Duration period) => (_since.elapsedMicroseconds % period.inMicroseconds) / period.inMicroseconds;
