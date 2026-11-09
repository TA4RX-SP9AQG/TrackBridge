import 'dart:async';
import 'package:flutter/foundation.dart';

import '../ble/tracker_link.dart';
import '../core/aprs.dart';
import '../core/aprs_position.dart';
import '../core/adif.dart';
import '../core/ascii_text.dart';
import '../core/ax25.dart';
import '../core/kiss_codec.dart';
import 'car_reply.dart';
import 'message_notifier.dart';
import 'message_store.dart';
import 'models.dart';
import 'station_table.dart';
import 'wavelog_client.dart';
import 'wavelog_preview.dart';
import 'phone_position.dart';
import 'settings_store.dart';
import '../l10n/app_strings.dart';

/// Glue between the Bluetooth link, the APRS protocol code and the UI.
///
/// Packets are never sent from here on their own except acknowledgements for
/// messages addressed to us (and only when [AppSettings.autoAck] is on). Every
/// other packet is built with a `build*` method, shown to the user, and sent
/// with [transmit].
class AppController extends ChangeNotifier {
  AppController({
    required this._link,
    required this._store,
    PositionProvider? positionProvider,
    DateTime Function()? now,
    MessageNotifier? notifier,
    this._messageStore,
    WavelogClient? wavelog,
    this._systemLanguage,
  })  : wavelog = wavelog ?? WavelogClient(),
        _notifier = notifier ?? const NoopMessageNotifier(),
        _positionProvider = positionProvider ?? readPhonePosition,
        _now = now ?? DateTime.now;

  /// Language code of the phone (e.g. `tr`). Null leaves the interface language untouched (tests).
  final String? _systemLanguage;

  /// The tracker's own beacons are sparse (its own interval), so its position stays usable this long.
  static const Duration maxTrackerFixAge = Duration(minutes: 10);

  static const int maxHeard = 200;
  static const Duration _ackThrottle = Duration(seconds: 10);

  /// Hard limits on automatic transmissions, so nobody on the air can make the
  /// station key up without bound.
  static const int maxAcksPerWindow = 10;
  static const Duration _ackWindow = Duration(minutes: 10);
  static const Duration _ackMinSpacing = Duration(seconds: 5);
  static const int _maxRemembered = 500;

  /// Spoken replies from the car: at most this many per window, and never closer than the minimum gap.
  static const int maxCarRepliesPerWindow = 10;
  static const Duration _carReplyWindow = Duration(minutes: 10);
  static const Duration _carReplyMinGap = Duration(seconds: 20);

  final TrackerLink _link;
  final SettingsStore _store;
  final PositionProvider _positionProvider;
  final DateTime Function() _now;

  AppSettings _settings = const AppSettings();
  TrackerFix? _trackerFix;
  KissDeframer _deframer = KissDeframer();
  List<HeardPacket> _heard = const <HeardPacket>[];
  Map<String, List<ChatMessage>> _conversations = const <String, List<ChatMessage>>{};
  StationTable _stations = const StationTable();
  final Map<String, DateTime> _lastAck = <String, DateTime>{};
  final Set<String> _seenIncoming = <String>{};
  final List<DateTime> _ackTimes = <DateTime>[];
  bool _disposed = false;
  final MessageNotifier _notifier;

  /// Wavelog logbook client (only used when the user asks to log a conversation).
  final WavelogClient wavelog;
  final MessageStore? _messageStore;
  final Map<String, int> _unread = <String, int>{};
  final List<DateTime> _carReplyTimes = <DateTime>[];
  bool _appInForeground = false;
  String? _activeChat;
  StreamSubscription<LinkInfo>? _infoSub;
  StreamSubscription<Uint8List>? _incomingSub;
  LinkStatus _lastStatus = LinkStatus.disconnected;
  int _nextMessageId = 1;
  String? _lastError;

  TrackerLink get link => _link;
  AppSettings get settings => _settings;

  /// The newest position the tracker's own GPS sent (null when none, or after a disconnect).
  TrackerFix? get trackerFix => _trackerFix;

  /// The tracker's position, or null when it has not sent one in the last [maxTrackerFixAge].
  GeoPoint? get freshTrackerPoint {
    final fix = _trackerFix;
    if (fix == null || _now().difference(fix.time) > maxTrackerFixAge) return null;
    return GeoPoint(fix.lat, fix.lon);
  }

  /// Our own position for the map: the fixed one, or the tracker's with the tracker source.
  GeoPoint? get ownPosition {
    if (_settings.positionSource == PositionSource.tracker) return freshTrackerPoint;
    final lat = _settings.manualLat;
    final lon = _settings.manualLon;
    return lat == null || lon == null ? null : GeoPoint(lat, lon);
  }
  LinkInfo get linkInfo => _link.info;

  /// Newest first.
  List<HeardPacket> get heard => _heard;
  Map<String, List<ChatMessage>> get conversations => _conversations;

  /// Stations, objects and items whose position the tracker heard, newest first.
  List<Station> get stations => _stations.all;
  String? get lastError => _lastError;

  /// Unread incoming messages from [peer] (0 when read or unknown).
  int unreadCount(String peer) => _unread[peer] ?? 0;
  int get totalUnread => _unread.values.fold<int>(0, (a, b) => a + b);

  Future<void> init() async {
    _settings = await _store.load();
    _applyLanguage();
    final stored = await _messageStore?.load();
    if (stored != null && stored.isNotEmpty) {
      _conversations = Map<String, List<ChatMessage>>.unmodifiable({
        for (final e in stored.entries) e.key: List<ChatMessage>.unmodifiable(e.value),
      });
      // Messages already stored count as seen, so a digipeated repeat after a restart is not shown again.
      for (final e in stored.entries) {
        for (final m in e.value) {
          if (m.direction == MessageDirection.incoming && m.messageId != null) _seenIncoming.add('${e.key}/${m.messageId}');
        }
      }
    }
    _nextMessageId = _now().millisecondsSinceEpoch ~/ 1000 % 90000 + 1;
    _infoSub = _link.infoStream.listen(_onLinkInfo);
    _incomingSub = _link.incoming.listen(_onBytes);
    notifyListeners();
  }

  /// Points the interface language at the stored preference (`system` follows the phone).
  void _applyLanguage() {
    if (_systemLanguage == null && _settings.language == 'system') return;
    L10n.setLanguage(AppLanguage.resolve(_settings.language, _systemLanguage));
  }

  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
    _applyLanguage();
    await _store.save(next);
    notifyListeners();
  }

  Future<void> connectTo(FoundTracker tracker) async {
    await _link.connect(tracker.id, name: tracker.name);
  }

  Future<void> disconnect() => _link.disconnect();

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  // ---- Wavelog ----

  /// The QSO that would be logged for the conversation with [peer], or null when there is none.
  WavelogQsoPreview? preview(String peer) {
    final list = _conversations[peer];
    if (list == null || list.isEmpty) return null;
    final first = list.reduce((a, b) => a.time.isBefore(b.time) ? a : b);
    final last = list.reduce((a, b) => a.time.isAfter(b.time) ? a : b);
    final mine = _settings.callsign;
    if (!isUsableCallsign(mine)) return null;
    final adif = buildAdifRecord(
      call: peer,
      myCall: mine,
      timeUtc: first.time.toUtc(),
      freqMhz: _settings.wavelogFreqMhz,
      comment: 'LoRa APRS mesajlasma (${list.length} mesaj), TrackBridge',
    );
    return WavelogQsoPreview(peer: peer, timeUtc: first.time.toUtc(), lastUtc: last.time.toUtc(), messageCount: list.length, adif: adif);
  }

  /// Sends the conversation with [peer] to the configured Wavelog logbook as a packet-radio QSO.
  Future<WavelogResult> logToWavelog(String peer) async {
    final config = _settings.wavelogConfig;
    if (!config.isComplete) {
      return WavelogResult(false, t('Önce Ayarlar > Wavelog bölümünü doldurun.'));
    }
    final WavelogQsoPreview? p;
    try {
      p = preview(peer);
    } on FormatException catch (e) {
      return WavelogResult(false, e.message);
    }
    if (p == null) {
      return WavelogResult(false, t('Bu istasyonla mesajlaşma yok ya da çağrı işareti ayarlı değil.'));
    }
    return wavelog.logQso(config, p.adif);
  }

  // ---- read state ----

  /// Set by the app lifecycle: true while the UI is visible.
  void setAppForeground(bool value) => _appInForeground = value;

  /// The conversation currently on screen, or null. Opening one marks it read.
  void setActiveChat(String? peer) {
    _activeChat = peer;
    if (peer != null) unawaited(markRead(peer));
  }

  /// Marks the conversation read and removes its notification (also in the car).
  Future<void> markRead(String peer) async {
    final had = _unread.remove(peer);
    if (had == null) return;
    notifyListeners();
    await _notifier.clear(peer);
  }

  // ---- spoken reply from the car ----

  /// Sends a reply dictated in the car. There is no confirmation dialog, so it is limited: off by
  /// default (`carVoiceReply`), only to a station that messaged us, plain ASCII, [kMaxMessageLength]
  /// characters, at least 20 s apart and at most [maxCarRepliesPerWindow] per 10 minutes.
  Future<CarReplyResult> replyFromCar(String peer, String text) async {
    if (!_settings.carVoiceReply) return const CarReplyResult.refused(CarReplyRefusal.disabled);
    if (!isUsableCallsign(_settings.callsign)) return const CarReplyResult.refused(CarReplyRefusal.noCallsign);
    final String key;
    try {
      key = normalizeCallsign(peer);
    } on FormatException {
      return const CarReplyResult.refused(CarReplyRefusal.unknownPeer);
    }
    final heardFromPeer = (_conversations[key] ?? const <ChatMessage>[]).any((m) => m.direction == MessageDirection.incoming);
    if (!heardFromPeer) return const CarReplyResult.refused(CarReplyRefusal.unknownPeer);
    if (!_link.info.isConnected) return const CarReplyResult.refused(CarReplyRefusal.notConnected);
    final ascii = toAprsAscii(text);
    if (ascii.isEmpty) return const CarReplyResult.refused(CarReplyRefusal.emptyText);

    final now = _now();
    _carReplyTimes.removeWhere((t) => now.difference(t) > _carReplyWindow);
    if (_carReplyTimes.isNotEmpty && now.difference(_carReplyTimes.last) < _carReplyMinGap) {
      return const CarReplyResult.refused(CarReplyRefusal.tooSoon);
    }
    if (_carReplyTimes.length >= maxCarRepliesPerWindow) return const CarReplyResult.refused(CarReplyRefusal.tooMany);

    try {
      final packet = buildMessagePacket(to: key, text: ascii);
      await transmit(packet);
      _carReplyTimes.add(now);
      return CarReplyResult.sent(ascii);
    } on Object {
      return const CarReplyResult.refused(CarReplyRefusal.failed);
    }
  }

  // ---- building packets ----

  Ax25Address _ownAddress() {
    if (!isUsableCallsign(_settings.callsign)) {
      throw FormatException(t('Önce Ayarlar\'dan kendi çağrı işaretinizi girin (örn. SP9AQG-9).'));
    }
    return Ax25Address.parse(_settings.callsign);
  }

  List<Ax25Address> _path() {
    final path = _settings.path
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(Ax25Address.parse)
        .toList(growable: false);
    if (path.length > Ax25Frame.maxDigipeaters) {
      throw FormatException(t('Yol (path) en fazla {v1} adım olabilir.', {'v1': Ax25Frame.maxDigipeaters}));
    }
    if (path.any((a) => a.repeated)) {
      throw FormatException(t('Yol (path) içinde * kullanılamaz.'));
    }
    return path;
  }

  OutgoingPacket _packet(String info, {String? peer, String? messageId, String? text}) {
    final frame = Ax25Frame(
      destination: Ax25Address.parse(kDefaultTocall),
      source: _ownAddress(),
      digipeaters: _path(),
      info: Uint8List.fromList(info.codeUnits),
    );
    return OutgoingPacket(
      tnc2: frame.toTnc2(),
      kiss: kissEncode(frame.encode()),
      peer: peer,
      messageId: messageId,
      text: text,
    );
  }

  String _plain(Ax25Address a) => Ax25Address(callsign: a.callsign, ssid: a.ssid).toString();

  /// Builds an APRS message to [to]. Throws [FormatException] with a
  /// user-facing message on invalid input.
  OutgoingPacket buildMessagePacket({required String to, required String text}) {
    final peer = normalizeCallsign(to);
    final id = '${_nextMessageId++}';
    if (_nextMessageId > 99999) _nextMessageId = 1;
    return _packet(buildMessageInfo(to: peer, text: text, id: id), peer: peer, messageId: id, text: text);
  }

  /// Builds a position beacon. With ambiguity > 0 the hidden digits are never
  /// part of the packet.
  Future<OutgoingPacket> buildBeaconPacket({GeoPoint? position}) async {
    final GeoPoint point;
    if (position != null) {
      point = position;
    } else {
      switch (_settings.positionSource) {
        case PositionSource.manual:
          final lat = _settings.manualLat;
          final lon = _settings.manualLon;
          if (lat == null || lon == null) {
            throw FormatException(t('Ayarlar\'dan sabit konum girin ya da telefon GPS\'ini seçin.'));
          }
          point = GeoPoint(lat, lon);
        case PositionSource.tracker:
          final fresh = freshTrackerPoint;
          if (fresh == null) {
            throw FormatException(t('Tracker henüz GPS konumu yayınlamadı. Tracker\'ın GPS\'i konum bulup kendi beacon\'ını attığında burada kullanılır.'));
          }
          point = fresh;
        case PositionSource.phone:
          try {
            point = await _positionProvider();
          } on StateError catch (e) {
            throw FormatException(e.message);
          } on Object catch (e) {
            throw FormatException(t('Konum alınamadı: {e}', {'e': e})); // timeouts, platform errors
          }
      }
    }
    return _packet(buildPositionInfo(
      lat: point.lat,
      lon: point.lon,
      symbolTable: _settings.symbolTable,
      symbol: _settings.symbol,
      comment: _settings.comment,
      ambiguity: _settings.ambiguity,
    ));
  }

  // ---- transmitting ----

  /// Writes [packet] to the tracker, which puts it on the air. Throws
  /// [StateError] when not connected.
  Future<void> transmit(OutgoingPacket packet) async {
    if (!_link.info.isConnected) throw StateError(t('Tracker bağlı değil.'));
    await _link.write(packet.kiss);
    final peer = packet.peer;
    if (peer != null) {
      _addMessage(ChatMessage(
        direction: MessageDirection.outgoing,
        peer: peer,
        text: packet.text ?? '',
        time: _now(),
        messageId: packet.messageId,
        state: DeliveryState.sent,
      ));
    }
  }

  // ---- receiving ----

  void _onLinkInfo(LinkInfo info) {
    if (info.status != _lastStatus) {
      _lastStatus = info.status;
      _deframer = KissDeframer(); // drop any half-received frame
      if (info.status != LinkStatus.connected) _trackerFix = null; // another tracker may come next
    }
    final id = info.deviceId;
    if (info.isConnected && id != null && id != _settings.lastDeviceId) {
      unawaited(updateSettings(_settings.copyWith(lastDeviceId: id, lastDeviceName: info.deviceName)));
    }
    notifyListeners();
  }

  void _onBytes(Uint8List bytes) {
    for (final kiss in _deframer.add(bytes)) {
      if (!kiss.isData) continue;
      final frame = Ax25Frame.decode(kiss.data);
      if (frame != null) _onFrame(frame);
    }
  }

  void _onFrame(Ax25Frame frame) {
    final now = _now();
    _heard = List<HeardPacket>.unmodifiable(
      <HeardPacket>[HeardPacket(tnc2: frame.toTnc2(), time: now), ..._heard].take(maxHeard),
    );
    final position = parsePositionFrame(frame);
    if (position != null) {
      _rememberTrackerFix(frame, position, now);
      _stations = _stations.update(
        Station.fromPacket(
          sender: _plain(frame.source),
          position: position,
          heardAt: now,
          path: frame.digipeaters.join(','),
          viaDigipeater: frame.digipeaters.any((d) => d.repeated),
        ),
        now,
      );
    }
    final info = String.fromCharCodes(frame.info);
    final message = info.startsWith(':') ? parseMessage(info) : null;
    if (message != null && _isCallsignSet) _handleMessage(frame, message, now);
    notifyListeners();
  }

  /// The firmware also sends the beacons it transmits itself (with its own GPS) to the phone.
  /// A copy that a digipeater repeated is somebody else's relay, not the tracker's GPS.
  void _rememberTrackerFix(Ax25Frame frame, AprsPosition position, DateTime now) {
    if (position.objectName != null || frame.digipeaters.any((d) => d.repeated)) return;
    final own = _trackerCallsignForMatching;
    if (own == null || _plain(frame.source) != own) return;
    _trackerFix = TrackerFix(lat: position.lat, lon: position.lon, time: now, speedKmh: position.speedKmh, courseDeg: position.courseDeg);
  }

  String? get _trackerCallsignForMatching {
    final configured = _settings.trackerCallsign.trim();
    final value = configured.isNotEmpty ? configured : _settings.callsign;
    return isUsableCallsign(value) ? normalizeCallsign(value) : null;
  }

  bool get _isCallsignSet => isUsableCallsign(_settings.callsign);

  void _handleMessage(Ax25Frame frame, AprsMessage message, DateTime now) {
    final ours = _plain(Ax25Address.parse(_settings.callsign));
    final sender = _plain(frame.source);
    if (sender == ours) {
      // Our own packet came back through a digipeater.
      if (message.kind == AprsMessageKind.message && message.id != null) {
        _updateOutgoing(message.addressee, message.id!, DeliveryState.heardBack);
      }
      return;
    }
    if (message.addressee.toUpperCase() != ours) return;
    switch (message.kind) {
      case AprsMessageKind.ack:
        _updateOutgoing(sender, message.id!, DeliveryState.acked);
      case AprsMessageKind.rej:
        _updateOutgoing(sender, message.id!, DeliveryState.rejected);
      case AprsMessageKind.message:
        _receiveMessage(sender, message, now);
    }
  }

  void _receiveMessage(String sender, AprsMessage message, DateTime now) {
    final id = message.id;
    final key = '$sender/$id';
    final replyAck = message.replyAckId;
    if (replyAck != null) _updateOutgoing(sender, replyAck, DeliveryState.acked);
    final isNew = id == null || _seenIncoming.add(key);
    if (_seenIncoming.length > _maxRemembered) _seenIncoming.remove(_seenIncoming.first);
    if (isNew) {
      _addMessage(ChatMessage(
        direction: MessageDirection.incoming,
        peer: sender,
        text: message.text,
        time: now,
        messageId: id,
      ));
      _announceIncoming(sender, message.text, now, id);
    }
    if (id != null && _settings.autoAck) {
      final last = _lastAck[key];
      if ((last == null || now.difference(last) >= _ackThrottle) && _ackAllowed(now)) {
        _lastAck[key] = now;
        _lastAck.removeWhere((_, t) => now.difference(t) > _ackWindow);
        unawaited(_sendAck(sender, id));
      }
    }
  }

  /// Counts the message as unread and shows it outside the app, unless the user is looking at that chat.
  void _announceIncoming(String peer, String text, DateTime time, String? id) {
    if (_appInForeground && _activeChat == peer) return;
    final unread = (_unread[peer] ?? 0) + 1;
    _unread[peer] = unread;
    unawaited(_notifier.showIncoming(peer: peer, text: text, time: time, unread: unread, messageId: id));
  }

  /// Global limit: minimum spacing between acks and a maximum per window.
  bool _ackAllowed(DateTime now) {
    _ackTimes.removeWhere((t) => now.difference(t) > _ackWindow);
    if (_ackTimes.length >= maxAcksPerWindow) return false;
    if (_ackTimes.isNotEmpty && now.difference(_ackTimes.last) < _ackMinSpacing) return false;
    _ackTimes.add(now);
    return true;
  }

  Future<void> _sendAck(String to, String id) async {
    try {
      final packet = _packet(buildAckInfo(to: to, id: id));
      await _link.write(packet.kiss);
    } on Object catch (e) {
      _lastError = t('Ack gönderilemedi: {e}', {'e': e});
      notifyListeners();
    }
  }

  // ---- conversation bookkeeping (immutable updates) ----

  void _addMessage(ChatMessage message) {
    final current = _conversations[message.peer] ?? const <ChatMessage>[];
    _conversations = Map<String, List<ChatMessage>>.unmodifiable({
      ..._conversations,
      message.peer: List<ChatMessage>.unmodifiable([...current, message]),
    });
    _persist();
    notifyListeners();
  }

  int _rank(DeliveryState s) => switch (s) {
        DeliveryState.none => 0,
        DeliveryState.failed => 0,
        DeliveryState.sent => 1,
        DeliveryState.heardBack => 2,
        DeliveryState.acked => 3,
        DeliveryState.rejected => 3,
      };

  void _updateOutgoing(String peer, String id, DeliveryState next) {
    final list = _conversations[peer];
    if (list == null) return;
    var changed = false;
    final updated = list.map((m) {
      if (m.direction == MessageDirection.outgoing && m.messageId == id && _rank(next) > _rank(m.state)) {
        changed = true;
        return m.withState(next);
      }
      return m;
    }).toList(growable: false);
    if (!changed) return;
    _conversations = Map<String, List<ChatMessage>>.unmodifiable({
      ..._conversations,
      peer: List<ChatMessage>.unmodifiable(updated),
    });
    _persist();
  }

  void _persist() {
    final store = _messageStore;
    if (store != null) unawaited(store.save(_conversations));
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_infoSub?.cancel());
    unawaited(_incomingSub?.cancel());
    super.dispose();
  }
}
