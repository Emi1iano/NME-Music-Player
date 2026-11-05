/// What a sync did, for the Sync screen.
class SyncOutcome {
  const SyncOutcome({
    required this.message,
    this.paired = false,
    this.completed = false,
    this.sent = 0,
    this.received = const [],
    this.incomplete = 0,
  });

  final String message;

  /// Connected to the other device at some point.
  final bool paired;

  /// Connected, and every song we had to send was confirmed by the other side.
  final bool completed;
  final int sent;

  /// File names of the songs that arrived (they are in the music folder).
  final List<String> received;

  /// Songs whose hash check failed on arrival (the backend keeps the file).
  final int incomplete;
}
