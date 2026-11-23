enum LaunchCode { ok, notInstalled, componentGone, romUnreadable, romPrivate, unsupportedFile, refused, crashed, unsupported }

/// What a snackbar offers next to a failed launch.
enum LaunchFix { none, detectAgain, chooseAnother, chooseFolder }

class LaunchResult {
  const LaunchResult(this.code, {this.message, this.extension, this.core});

  static const ok = LaunchResult(LaunchCode.ok);

  final LaunchCode code;

  /// The exception's message for [LaunchCode.refused], the stderr tail for
  /// [LaunchCode.crashed].
  final String? message;

  /// For [LaunchCode.unsupportedFile]: the file's extension, no dot.
  final String? extension;

  /// For [LaunchCode.unsupportedFile] on desktop: the missing RetroArch core.
  final String? core;

  /// The native `launch` reply, `{code, message}`. An unknown code is a
  /// refusal: the launch did not happen as asked.
  static LaunchResult fromReply(Object? reply) {
    final map = reply is Map ? reply : const {};
    final name = map['code'];
    final message = map['message'] is String ? map['message'] as String : null;
    for (final c in LaunchCode.values) {
      if (c.name == name) return LaunchResult(c, message: message);
    }
    return LaunchResult(LaunchCode.refused, message: message ?? 'unexpected reply: $reply');
  }

  /// The line the user reads, and the fix offered beside it, for a launch of
  /// [emulator]. Null text for [LaunchCode.ok]: nothing to say.
  ({String? text, LaunchFix fix}) describe(String emulator) => switch (code) {
        LaunchCode.ok => (text: null, fix: LaunchFix.none),
        LaunchCode.notInstalled => (text: '$emulator is not installed anymore', fix: LaunchFix.detectAgain),
        LaunchCode.componentGone => (text: '$emulator changed in this version', fix: LaunchFix.chooseAnother),
        LaunchCode.romUnreadable => (text: 'Cannot read the file', fix: LaunchFix.none),
        LaunchCode.romPrivate => (text: 'Move your library out of Android/data', fix: LaunchFix.chooseFolder),
        LaunchCode.unsupportedFile => (
            text: core != null ? '$emulator has no $core core' : '$emulator does not open .${extension ?? '?'}',
            fix: LaunchFix.chooseAnother,
          ),
        LaunchCode.refused => (text: message ?? '$emulator refused the launch', fix: LaunchFix.chooseAnother),
        LaunchCode.crashed => (text: message == null || message!.isEmpty ? '$emulator closed right away' : '$emulator closed right away:\n$message', fix: LaunchFix.none),
        LaunchCode.unsupported => (text: 'Launching is not available here', fix: LaunchFix.none),
      };

  @override
  String toString() => 'LaunchResult(${code.name}${message == null ? '' : ', $message'})';
}
