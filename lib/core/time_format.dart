String _two(int v) => v.toString().padLeft(2, '0');

/// "18:40".
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "18:40:05".
String formatClockSeconds(DateTime t) => '${formatClock(t)}:${_two(t.second)}';
