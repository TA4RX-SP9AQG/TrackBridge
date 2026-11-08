import 'dart:async';
import 'package:flutter/foundation.dart';

import '../ble/tracker_link.dart';
import '../core/aprs.dart';
import '../core/aprs_position.dart';
import '../core/ax25.dart';
import '../core/kiss_codec.dart';
import 'models.dart';
import 'station_table.dart';
import 'phone_position.dart';
import 'settings_store.dart';

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
  })  : _positionProvider = positionProvider ?? readPhonePosition,
        _now = now ?? DateTime.now;

  static const int maxHeard = 200;
  static const Duration _ackThrottle = Duration(seconds: 10);

  /// Hard limits on automatic transmissions, so nobody on the air can make the
  /// station key up without bound.
  static const int maxAcksPerWindow = 10;
  static const Duration _ackWindow = Duration(minutes: 10);
  static const Duration _ackMinSpacing = Duration(seconds: 5);
  static const int _maxRemembered = 500;

  final TrackerLink _link;
  final SettingsStore _store;
  final PositionProvider _positionProvider;
  final DateTime Function() _now;

  AppSettings _settings = const AppSettings();
  KissDeframer _deframer = KissDeframer();
  List<HeardPacket> _heard = const <HeardPacket>[];
  Map<String, List<ChatMessage>> _conversations = const <String, List<ChatMessage>>{};
  StationTable _stations = const StationTable();
  final Map<String, DateTime> _lastAck = <String, DateTime>{};
  final Set<String> _seenIncoming = <String>{};
  final List<DateTime> _ackTimes = <DateTime>[];
  bool _disposed = false;
  StreamSubscription<LinkInfo>? _infoSub;
  StreamSubscription<Uint8List>? _incomingSub;
  LinkStatus _lastStatus = LinkStatus.disconnected;
  int _nextMessageId = 1;
  String? _lastError;

  TrackerLink get link => _link;
  AppSettings get settings => _settings;
  LinkInfo get linkInfo => _link.info;

  /// Newest first.
  List<HeardPacket> get heard => _heard;
  Map<String, List<ChatMessage>> get conversations => _conversations;

  /// Stations, objects and items whose position the tracker heard, newest first.
  List<Station> get stations => _stations.all;
  String? get lastError => _lastError;

  Future<void> init() async {
    _settings = await _store.load();
    _nextMessageId = _now().millisecondsSinceEpoch ~/ 1000 % 90000 + 1;
    _infoSub = _link.infoStream.listen(_onLinkInfo);
    _incomingSub = _link.incoming.listen(_onBytes);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
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

  // ---- building packets ----

  Ax25Address _ownAddress() {
    if (!isUsableCallsign(_settings.callsign)) {
      throw const FormatException('Önce Ayarlar\'dan kendi çağrı işaretinizi girin (örn. SP9AQG-9).');
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
      throw const FormatException('Yol (path) en fazla ${Ax25Frame.maxDigipeaters} adım olabilir.');
    }
    if (path.any((a) => a.repeated)) {
      throw const FormatException('Yol (path) içinde * kullanılamaz.');
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
  Future<OutgoingPacket> buildBeaconPacket() async {
    final GeoPoint point;
    switch (_settings.positionSource) {
      case PositionSource.manual:
        final lat = _settings.manualLat;
        final lon = _settings.manualLon;
        if (lat == null || lon == null) {
          throw const FormatException('Ayarlar\'dan sabit konum girin ya da telefon GPS\'ini seçin.');
        }
        point = GeoPoint(lat, lon);
      case PositionSource.phone:
        try {
          point = await _positionProvider();
        } on StateError catch (e) {
          throw FormatException(e.message);
        } on Object catch (e) {
          throw FormatException('Konum alınamadı: $e'); // timeouts, platform errors
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
    if (!_link.info.isConnected) throw StateError('Tracker bağlı değil.');
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
      _lastError = 'Ack gönderilemedi: $e';
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
