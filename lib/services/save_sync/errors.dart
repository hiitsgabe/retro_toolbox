/// The action cannot run now; nothing changed. The message is for the user.
class SyncBlocked implements Exception {
  SyncBlocked(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// A pull refused before touching the game folder.
class PullRefused implements Exception {
  PullRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// A pull failed after it started writing; the previous files were put back from [historyEntry].
class PullRolledBack implements Exception {
  PullRolledBack(this.cause, this.historyEntry, {this.rollbackError});

  final Object cause;
  final String historyEntry;
  final Object? rollbackError;

  @override
  String toString() => rollbackError == null
      ? 'Pull failed and was rolled back: $cause'
      : 'Pull failed ($cause) and putting the old files back failed too ($rollbackError). They are in $historyEntry';
}
