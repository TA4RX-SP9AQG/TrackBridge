import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/adif.dart';
import 'package:trackbridge/state/wavelog_client.dart';

void main() {
  group('ADIF', () {
    final when = DateTime.utc(2026, 11, 9, 7, 5, 9);

    test('a field is <NAME:length>value', () {
      expect(adifField('CALL', 'TA4RX'), '<CALL:5>TA4RX');
      expect(adifField('COMMENT', ''), '');
    });

    test('builds an APRS packet QSO record with UTC date and time', () {
      final r = buildAdifRecord(
        call: 'TA4RX-7',
        myCall: 'SP9AQG-9',
        timeUtc: when,
        freqMhz: 433.775,
        comment: 'APRS mesaji',
      );
      expect(r, contains('<CALL:5>TA4RX'));
      expect(r, contains('<STATION_CALLSIGN:6>SP9AQG'));
      expect(r, contains('<QSO_DATE:8>20261109'));
      expect(r, contains('<TIME_ON:6>070509'));
      expect(r, contains('<MODE:3>PKT'));
      expect(r, contains('<FREQ:7>433.775'));
      expect(r, contains('<BAND:4>70cm'));
      expect(r, contains('<COMMENT:11>APRS mesaji'));
      expect(r, endsWith('<EOR>'));
    });

    test('the SSID is removed from both callsigns', () {
      final r = buildAdifRecord(call: 'n1test-12', myCall: 'sp9aqg-9', timeUtc: when, freqMhz: 433.775);
      expect(r, contains('<CALL:6>N1TEST'));
      expect(r, contains('<STATION_CALLSIGN:6>SP9AQG'));
    });

    test('a local time is converted to UTC', () {
      final local = DateTime(2026, 11, 9, 23, 30).toUtc();
      final r = buildAdifRecord(call: 'A1B', myCall: 'C2D', timeUtc: local, freqMhz: 433.775);
      expect(r, contains('<QSO_DATE:8>${local.year}${local.month.toString().padLeft(2, '0')}${local.day.toString().padLeft(2, '0')}'));
    });

    test('lengths always match, also for text with non-ASCII characters (which are dropped)', () {
      final r = buildAdifRecord(call: 'A1B', myCall: 'C2D', timeUtc: when, freqMhz: 433.775, comment: 'Merhaba dünya ğ');
      final m = RegExp(r'<COMMENT:(\d+)>([^<]*)').firstMatch(r)!;
      expect(int.parse(m.group(1)!), m.group(2)!.length);
      expect(m.group(2), isNot(contains('ü')));
    });

    test('angle brackets in the comment cannot break out of the field', () {
      final r = buildAdifRecord(call: 'A1B', myCall: 'C2D', timeUtc: when, freqMhz: 433.775, comment: 'a<b>c<EOR>');
      expect(RegExp('<EOR>').allMatches(r).length, 1);
    });

    test('bands from frequency', () {
      expect(adifBand(433.775), '70cm');
      expect(adifBand(144.8), '2m');
      expect(adifBand(868.0), '33cm');
      expect(adifBand(7.1), '40m');
      expect(adifBand(1296), '23cm');
      expect(adifBand(0), '');
      expect(adifBand(99999), '');
    });

    test('rejects callsigns that are not valid', () {
      expect(() => buildAdifRecord(call: 'not a call', myCall: 'SP9AQG', timeUtc: when, freqMhz: 433.775), throwsFormatException);
      expect(() => buildAdifRecord(call: 'TA4RX', myCall: '', timeUtc: when, freqMhz: 433.775), throwsFormatException);
    });
  });

  group('WavelogConfig', () {
    test('endpoint normalisation', () {
      expect(WavelogConfig.endpoint('https://log.example.com', 'api/qso').toString(), 'https://log.example.com/index.php/api/qso');
      expect(WavelogConfig.endpoint('https://log.example.com/', 'api/qso').toString(), 'https://log.example.com/index.php/api/qso');
      expect(WavelogConfig.endpoint('https://example.com/wavelog/index.php', 'api/qso').toString(),
          'https://example.com/wavelog/index.php/api/qso');
      expect(WavelogConfig.endpoint(' https://log.example.com/wavelog ', 'api/version').toString(),
          'https://log.example.com/wavelog/index.php/api/version');
    });

    test('https is required except for local network hosts', () {
      expect(WavelogConfig.urlProblem('https://log.example.com'), isNull);
      expect(WavelogConfig.urlProblem('http://log.example.com'), isNotNull);
      expect(WavelogConfig.urlProblem('http://192.168.1.20/wavelog'), isNull);
      expect(WavelogConfig.urlProblem('http://10.0.0.5'), isNull);
      expect(WavelogConfig.urlProblem('http://localhost:8080'), isNull);
      expect(WavelogConfig.urlProblem('ftp://x.com'), isNotNull);
      expect(WavelogConfig.urlProblem('not a url'), isNotNull);
      expect(WavelogConfig.urlProblem(''), isNotNull);
    });

    test('complete() needs url, key, profile id and a frequency', () {
      const ok = WavelogConfig(url: 'https://l.example.com', apiKey: 'k', stationProfileId: '1', freqMhz: 433.775);
      expect(ok.isComplete, isTrue);
      expect(const WavelogConfig(url: '', apiKey: 'k', stationProfileId: '1', freqMhz: 433.775).isComplete, isFalse);
      expect(const WavelogConfig(url: 'https://l.example.com', apiKey: '', stationProfileId: '1', freqMhz: 433.775).isComplete, isFalse);
      expect(const WavelogConfig(url: 'https://l.example.com', apiKey: 'k', stationProfileId: 'x', freqMhz: 433.775).isComplete, isFalse);
      expect(const WavelogConfig(url: 'https://l.example.com', apiKey: 'k', stationProfileId: '1', freqMhz: 0).isComplete, isFalse);
    });
  });

  group('WavelogClient', () {
    const config = WavelogConfig(url: 'https://log.example.com', apiKey: 'SECRETKEY', stationProfileId: '3', freqMhz: 433.775);

    late Uri sentUri;
    late Map<String, String> sentHeaders;
    late String sentBody;

    WavelogClient client(HttpReply Function() reply) => WavelogClient(post: (uri, headers, body) async {
          sentUri = uri;
          sentHeaders = headers;
          sentBody = body;
          return reply();
        });

    test('posts the ADIF record with the documented JSON body and headers', () async {
      final c = client(() => const HttpReply(200, '{"status":"created","adif_count":1}'));
      final r = await c.logQso(config, '<CALL:5>TA4RX<EOR>');
      expect(sentUri.toString(), 'https://log.example.com/index.php/api/qso');
      expect(sentHeaders['Content-Type'], 'application/json');
      expect(sentHeaders['Accept'], 'application/json');
      final body = jsonDecode(sentBody) as Map<String, Object?>;
      expect(body['key'], 'SECRETKEY');
      expect(body['station_profile_id'], '3');
      expect(body['type'], 'adif');
      expect(body['string'], '<CALL:5>TA4RX<EOR>');
      expect(r.ok, isTrue);
    });

    test('a server-side refusal is reported with its reason', () async {
      final c = client(() => const HttpReply(401, '{"status":"failed","reason":"missing or invalid api key"}'));
      final r = await c.logQso(config, 'x');
      expect(r.ok, isFalse);
      expect(r.message, contains('invalid api key'));
    });

    test('an unexpected 200 answer is not claimed as success', () async {
      final r = await client(() => const HttpReply(200, '<html>login</html>')).logQso(config, 'x');
      expect(r.ok, isFalse);
      expect(r.message, contains('anlaşılamadı'));
    });

    test('network errors and timeouts become a readable failure', () async {
      final c = WavelogClient(post: (_, _, _) async => throw const HttpFailure('timeout'));
      final r = await c.logQso(config, 'x');
      expect(r.ok, isFalse);
      expect(r.message, contains('ulaşılamadı'));
    });

    test('the API key never appears in a result message', () async {
      final c = client(() => const HttpReply(500, 'error for SECRETKEY'));
      final r = await c.logQso(config, 'x');
      expect(r.message, isNot(contains('SECRETKEY')));
    });

    test('refuses to send with an incomplete or insecure configuration', () async {
      var called = false;
      final c = WavelogClient(post: (_, _, _) async {
        called = true;
        return const HttpReply(200, '{}');
      });
      expect((await c.logQso(const WavelogConfig(url: '', apiKey: '', stationProfileId: '', freqMhz: 0), 'x')).ok, isFalse);
      expect((await c.logQso(const WavelogConfig(url: 'http://log.example.com', apiKey: 'k', stationProfileId: '1', freqMhz: 433.775), 'x')).ok, isFalse);
      expect(called, isFalse);
    });

    test('connection test uses api/version with the key and accepts status ok', () async {
      final c = client(() => const HttpReply(200, '{"status":"ok","version":"2.0"}'));
      final r = await c.testConnection(config);
      expect(sentUri.toString(), 'https://log.example.com/index.php/api/version');
      expect((jsonDecode(sentBody) as Map)['key'], 'SECRETKEY');
      expect(r.ok, isTrue);
      expect(r.message, contains('2.0'));
    });

    test('connection test reports a bad key', () async {
      final r = await client(() => const HttpReply(401, '{"status":"failed","reason":"missing or invalid api key"}')).testConnection(config);
      expect(r.ok, isFalse);
    });
  });
}
