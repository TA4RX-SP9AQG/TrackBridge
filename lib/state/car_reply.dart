/// Why a spoken reply from the car was not sent.
enum CarReplyRefusal { disabled, noCallsign, unknownPeer, notConnected, emptyText, tooSoon, tooMany, failed }

/// Outcome of [AppController.replyFromCar]. [spoken] is short Turkish text meant to be read
/// back to the driver.
class CarReplyResult {
  const CarReplyResult.sent(String text)
      : sent = true,
        refusal = null,
        sentText = text;

  const CarReplyResult.refused(CarReplyRefusal reason)
      : sent = false,
        refusal = reason,
        sentText = null;

  final bool sent;
  final CarReplyRefusal? refusal;

  /// The text that went on the air (already converted to ASCII).
  final String? sentText;

  String get spoken => switch (refusal) {
        null => 'Yanıt gönderildi.',
        CarReplyRefusal.disabled => 'Arabadan sesli yanıt kapalı. Ayarlardan açabilirsiniz.',
        CarReplyRefusal.noCallsign => 'Çağrı işareti ayarlı değil, yanıt gönderilemedi.',
        CarReplyRefusal.unknownPeer => 'Bu istasyondan mesaj gelmediği için yanıt gönderilmedi.',
        CarReplyRefusal.notConnected => 'Tracker bağlı değil, yanıt gönderilemedi.',
        CarReplyRefusal.emptyText => 'Yanıt boş kaldığı için gönderilmedi.',
        CarReplyRefusal.tooSoon => 'Çok hızlı. Yirmi saniye bekleyin.',
        CarReplyRefusal.tooMany => 'Yanıt sınırına ulaşıldı. On dakika sonra tekrar deneyin.',
        CarReplyRefusal.failed => 'Yanıt gönderilemedi.',
      };
}
