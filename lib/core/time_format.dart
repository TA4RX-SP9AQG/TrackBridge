String _two(int v) => v.toString().padLeft(2, '0');

/// "18:40".
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "18:40:05".
String formatClockSeconds(DateTime t) => '${formatClock(t)}:${_two(t.second)}';

/// "5:03" or "1:02:09". Negative durations are shown as "0:00".
String formatDuration(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final sec = total % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(sec)}' : '$m:${_two(sec)}';
}
