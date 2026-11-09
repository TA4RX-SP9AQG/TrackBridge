import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Persists conversations so they survive the process being killed.
abstract class MessageStore {
  Future<Map<String, List<ChatMessage>>> load();
  Future<void> save(Map<String, List<ChatMessage>> conversations);
}

class PrefsMessageStore implements MessageStore {
  static const String _key = 'tb.messages';
  static const int perPeerCap = 200;
  static const int totalCap = 500;

  @override
  Future<Map<String, List<ChatMessage>>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return const <String, List<ChatMessage>>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return {
        for (final e in decoded.entries)
          e.key: [for (final m in (e.value! as List<Object?>)) ChatMessage.fromJson(Map<String, Object?>.from(m! as Map))],
      };
    } on Object {
      return const <String, List<ChatMessage>>{}; // corrupt data must never stop the app from starting
    }
  }

  @override
  Future<void> save(Map<String, List<ChatMessage>> conversations) async {
    final trimmed = trim(conversations);
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({for (final e in trimmed.entries) e.key: [for (final m in e.value) m.toJson()]}),
    );
  }

  /// Keeps at most [perPeerCap] messages per peer and [totalCap] overall,
  /// dropping the oldest first, and removes peers left empty.
  static Map<String, List<ChatMessage>> trim(Map<String, List<ChatMessage>> input) {
    final perPeer = <String, List<ChatMessage>>{
      for (final e in input.entries)
        if (e.value.isNotEmpty) e.key: e.value.length > perPeerCap ? e.value.sublist(e.value.length - perPeerCap) : e.value,
    };
    final total = perPeer.values.fold<int>(0, (n, l) => n + l.length);
    if (total <= totalCap) return perPeer;
    final all = <(String, ChatMessage)>[
      for (final e in perPeer.entries) for (final m in e.value) (e.key, m),
    ]..sort((a, b) => a.$2.time.compareTo(b.$2.time));
    final keep = all.sublist(all.length - totalCap);
    final result = <String, List<ChatMessage>>{};
    for (final (peer, m) in keep) {
      (result[peer] ??= <ChatMessage>[]).add(m);
    }
    return result;
  }
}
