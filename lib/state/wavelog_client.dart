import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../l10n/app_strings.dart';

/// What a Wavelog server needs from this app.
class WavelogConfig {
  const WavelogConfig({required this.url, required this.apiKey, required this.stationProfileId, required this.freqMhz});

  final String url;

  /// A read+write Wavelog API key. Stored on the phone only.
  final String apiKey;
  final String stationProfileId;

  /// LoRa APRS frequency written into the QSO (for example 433.775 in Europe).
  final double freqMhz;

  bool get isComplete =>
      urlProblem(url) == null && apiKey.trim().isNotEmpty && int.tryParse(stationProfileId.trim()) != null && freqMhz > 0;

  /// Host name of the server, for showing where data goes.
  String get host => Uri.tryParse(url.trim())?.host ?? '';

  /// `https://host/path` + `/index.php/` + [api]; a trailing slash or `index.php` in [base] is tolerated.
  static Uri endpoint(String base, String api) {
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/index.php')) b = b.substring(0, b.length - '/index.php'.length);
    return Uri.parse('$b/index.php/$api');
  }

  /// null when [url] is acceptable: https, or http only for hosts on the local network.
  static String? urlProblem(String url) {
    final text = url.trim();
    if (text.isEmpty) return t('Wavelog adresi boş.');
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return t('Adres geçersiz.');
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http' && _isLocalHost(uri.host)) return null;
    return t('Adres https:// ile başlamalı (yalnızca yerel ağda http kabul edilir).');
  }

  static bool _isLocalHost(String host) {
    if (host == 'localhost' || host.endsWith('.local')) return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final n = parts.map(int.tryParse).toList();
    if (n.any((v) => v == null || v < 0 || v > 255)) return false;
    final a = n[0]!;
    final b = n[1]!;
    return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }
}

class HttpReply {
  const HttpReply(this.status, this.body);

  final int status;
  final String body;
}

class HttpFailure implements Exception {
  const HttpFailure(this.reason);

  final String reason;
}

/// POSTs JSON. Throws [HttpFailure] on network problems and timeouts. Replaced in tests.
typedef HttpPost = Future<HttpReply> Function(Uri uri, Map<String, String> headers, String body);

Future<HttpReply> defaultHttpPost(Uri uri, Map<String, String> headers, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(uri).timeout(const Duration(seconds: 15));
    headers.forEach(request.headers.set);
    request.add(utf8.encode(body));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final text = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    return HttpReply(response.statusCode, text);
  } on TimeoutException {
    throw const HttpFailure('timeout');
  } on SocketException catch (e) {
    throw HttpFailure(e.message);
  } on HandshakeException catch (e) {
    throw HttpFailure(e.message);
  } on HttpException catch (e) {
    throw HttpFailure(e.message);
  } finally {
    client.close(force: true);
  }
}

class WavelogResult {
  const WavelogResult(this.ok, this.message);

  final bool ok;
  final String message;
}

/// Sends QSOs to a Wavelog server (`api/qso`, `api/version`). Only ever called because the user asked.
class WavelogClient {
  WavelogClient({HttpPost? post}) : _post = post ?? defaultHttpPost;

  final HttpPost _post;

  static const Map<String, String> _headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};

  String? _precheck(WavelogConfig c) {
    final problem = WavelogConfig.urlProblem(c.url);
    if (problem != null) return problem;
    if (!c.isComplete) return t('Wavelog ayarları eksik (adres, API anahtarı, istasyon profil numarası, frekans).');
    return null;
  }

  Future<WavelogResult> logQso(WavelogConfig c, String adif) async {
    final problem = _precheck(c);
    if (problem != null) return WavelogResult(false, problem);
    final body = jsonEncode(<String, Object?>{
      'key': c.apiKey.trim(),
      'station_profile_id': c.stationProfileId.trim(),
      'type': 'adif',
      'string': adif,
    });
    final reply = await _send(c, WavelogConfig.endpoint(c.url, 'api/qso'), body);
    if (reply is WavelogResult) return reply;
    return _judgeQso(c, reply as HttpReply);
  }

  Future<WavelogResult> testConnection(WavelogConfig c) async {
    final problem = WavelogConfig.urlProblem(c.url);
    if (problem != null) return WavelogResult(false, problem);
    if (c.apiKey.trim().isEmpty) return WavelogResult(false, t('API anahtarı boş.'));
    final reply = await _send(c, WavelogConfig.endpoint(c.url, 'api/version'), jsonEncode({'key': c.apiKey.trim()}));
    if (reply is WavelogResult) return reply;
    final r = reply as HttpReply;
    final json = _json(r.body);
    if (r.status >= 200 && r.status < 300 && json?['status'] == 'ok') {
      return WavelogResult(true, t('Bağlantı tamam (Wavelog API {v1}).', {'v1': json?['version'] ?? ''}).replaceAll(' )', ')'));
    }
    return WavelogResult(false, _failure(c, r));
  }

  Future<Object> _send(WavelogConfig c, Uri uri, String body) async {
    try {
      return await _post(uri, _headers, body);
    } on HttpFailure {
      return WavelogResult(false, t('Wavelog sunucusuna ulaşılamadı ({v1}). Adres ve internet bağlantısını kontrol edin.', {'v1': c.host}));
    }
  }

  WavelogResult _judgeQso(WavelogConfig c, HttpReply r) {
    final json = _json(r.body);
    final status = json?['status'];
    if (r.status >= 200 && r.status < 300 && (status == 'created' || status == 'ok')) {
      return const WavelogResult(true, 'Wavelog\'a kaydedildi.');
    }
    if (r.status >= 200 && r.status < 300 && json == null) {
      return WavelogResult(false, t('Sunucu yanıtı anlaşılamadı; kayıt yapıldığı doğrulanamadı.'));
    }
    return WavelogResult(false, _failure(c, r));
  }

  String _failure(WavelogConfig c, HttpReply r) {
    final json = _json(r.body);
    final reason = json?['reason'] ?? json?['message'];
    final text = (reason is String && reason.isNotEmpty ? reason : 'HTTP ${r.status}').replaceAll(c.apiKey.trim(), '***');
    return 'Wavelog reddetti: $text';
  }

  Map<String, Object?>? _json(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
