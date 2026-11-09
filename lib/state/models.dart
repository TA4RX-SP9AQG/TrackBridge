import 'dart:typed_data';

import '../core/tile_url.dart';

enum PositionSource { manual, phone }

/// User settings. Immutable; use [copyWith].
class AppSettings {
  const AppSettings({
    this.callsign = '',
    this.path = 'WIDE1-1',
    this.symbolTable = '/',
    this.symbol = '-',
    this.comment = 'TrackBridge',
    this.ambiguity = 2,
    this.positionSource = PositionSource.manual,
    this.manualLat,
    this.manualLon,
    this.autoAck = true,
    this.carVoiceReply = false,
    this.noticeAccepted = false,
    this.lastDeviceId,
    this.lastDeviceName,
    this.tileUrl = kDefaultTileUrl,
  });

  /// Our station, `CALL-SSID`.
  final String callsign;

  /// Comma separated digipeater path, may be empty.
  final String path;
  final String symbolTable;
  final String symbol;
  final String comment;

  /// APRS position ambiguity 0-4 (2 is roughly 2 km).
  final int ambiguity;
  final PositionSource positionSource;
  final double? manualLat;
  final double? manualLon;

  /// Answer messages addressed to us with an ack (the only automatic transmission).
  final bool autoAck;

  /// Lets Android Auto send a spoken reply to a message you received (transmits without a dialog). Off by default.
  final bool carVoiceReply;

  /// The amateur-radio licence notice was accepted.
  final bool noticeAccepted;
  final String? lastDeviceId;
  final String? lastDeviceName;

  /// Map tile URL template with {z}/{x}/{y}.
  final String tileUrl;

  AppSettings copyWith({
    String? callsign,
    String? path,
    String? symbolTable,
    String? symbol,
    String? comment,
    int? ambiguity,
    PositionSource? positionSource,
    double? manualLat,
    double? manualLon,
    bool? autoAck,
    bool? carVoiceReply,
    bool? noticeAccepted,
    String? lastDeviceId,
    String? lastDeviceName,
    String? tileUrl,
  }) =>
      AppSettings(
        callsign: callsign ?? this.callsign,
        path: path ?? this.path,
        symbolTable: symbolTable ?? this.symbolTable,
        symbol: symbol ?? this.symbol,
        comment: comment ?? this.comment,
        ambiguity: ambiguity ?? this.ambiguity,
        positionSource: positionSource ?? this.positionSource,
        manualLat: manualLat ?? this.manualLat,
        manualLon: manualLon ?? this.manualLon,
        autoAck: autoAck ?? this.autoAck,
        carVoiceReply: carVoiceReply ?? this.carVoiceReply,
        noticeAccepted: noticeAccepted ?? this.noticeAccepted,
        lastDeviceId: lastDeviceId ?? this.lastDeviceId,
        lastDeviceName: lastDeviceName ?? this.lastDeviceName,
        tileUrl: tileUrl ?? this.tileUrl,
      );
}

/// A packet ready to be transmitted, shown to the user before sending.
class OutgoingPacket {
  const OutgoingPacket({required this.tnc2, required this.kiss, this.peer, this.messageId, this.text});

  /// For messages: the plain message text (without the `{id` suffix).
  final String? text;

  /// Human readable form, shown in the confirmation dialog.
  final String tnc2;

  /// Bytes to write to the tracker.
  final Uint8List kiss;

  /// For messages: the other station and our message number.
  final String? peer;
  final String? messageId;
}

enum MessageDirection { incoming, outgoing }

enum DeliveryState { none, sent, heardBack, acked, rejected, failed }

class ChatMessage {
  const ChatMessage({
    required this.direction,
    required this.peer,
    required this.text,
    required this.time,
    this.messageId,
    this.state = DeliveryState.none,
  });

  final MessageDirection direction;
  final String peer;
  final String text;
  final DateTime time;
  final String? messageId;
  final DeliveryState state;

  Map<String, Object?> toJson() => <String, Object?>{
        'd': direction.name,
        'p': peer,
        't': text,
        'ms': time.millisecondsSinceEpoch,
        if (messageId != null) 'id': messageId,
        's': state.name,
      };

  /// Throws [FormatException] when [json] is not a stored message.
  factory ChatMessage.fromJson(Map<String, Object?> json) {
    final direction = MessageDirection.values.where((v) => v.name == json['d']).firstOrNull;
    final state = DeliveryState.values.where((v) => v.name == json['s']).firstOrNull;
    final peer = json['p'];
    final text = json['t'];
    final ms = json['ms'];
    if (direction == null || state == null || peer is! String || text is! String || ms is! int) {
      throw const FormatException('Kayıtlı mesaj okunamadı.');
    }
    final id = json['id'];
    return ChatMessage(
      direction: direction,
      peer: peer,
      text: text,
      time: DateTime.fromMillisecondsSinceEpoch(ms),
      messageId: id is String ? id : null,
      state: state,
    );
  }

  ChatMessage withState(DeliveryState next) => ChatMessage(
        direction: direction,
        peer: peer,
        text: text,
        time: time,
        messageId: messageId,
        state: next,
      );
}

/// A packet the tracker heard on the radio (or our own packet repeated back).
class HeardPacket {
  const HeardPacket({required this.tnc2, required this.time});

  final String tnc2;
  final DateTime time;
}
