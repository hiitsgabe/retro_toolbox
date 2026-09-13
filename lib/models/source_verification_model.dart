/// The a-posteriori confidence axis for a source: what the CRC check said
/// after reading the remote file header.
///
/// Distinct from `MatchConfidence`, the a-priori name-tier axis; the two do
/// not mix. If you want to add a `crcOk` to `MatchConfidence`, this is the
/// enum you meant.
enum SourceVerification {
  /// Nobody asked. The state of every source outside the detail screen.
  notVerified,

  /// Both requests are in flight.
  verifying,

  /// A dump of this game is inside. Certainty, not a guess.
  crcOk,

  /// The CRC was read and is not this game's. The source drops out of the
  /// highlight and down into the list, marked.
  crcDiscarded,

  /// Undeterminable: no `Range`, not a ZIP, ZIP without a ROM inside. Not a
  /// synonym for a bad source, so it does not discard.
  impossible,
}
