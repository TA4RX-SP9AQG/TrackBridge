/// What logging a conversation to Wavelog would send. Shown to the user before anything leaves the phone.
class WavelogQsoPreview {
  const WavelogQsoPreview({
    required this.peer,
    required this.timeUtc,
    required this.lastUtc,
    required this.messageCount,
    required this.adif,
  });

  final String peer;

  /// First message of the conversation (the QSO start), UTC.
  final DateTime timeUtc;
  final DateTime lastUtc;
  final int messageCount;
  final String adif;
}
