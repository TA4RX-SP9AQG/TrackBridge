import '../l10n/app_strings.dart';
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
        null => t('Yanıt gönderildi.'),
        CarReplyRefusal.disabled => t('Arabadan sesli yanıt kapalı. Ayarlardan açabilirsiniz.'),
        CarReplyRefusal.noCallsign => t('Çağrı işareti ayarlı değil, yanıt gönderilemedi.'),
        CarReplyRefusal.unknownPeer => t('Bu istasyondan mesaj gelmediği için yanıt gönderilmedi.'),
        CarReplyRefusal.notConnected => t('Tracker bağlı değil, yanıt gönderilemedi.'),
        CarReplyRefusal.emptyText => t('Yanıt boş kaldığı için gönderilmedi.'),
        CarReplyRefusal.tooSoon => t('Çok hızlı. Yirmi saniye bekleyin.'),
        CarReplyRefusal.tooMany => t('Yanıt sınırına ulaşıldı. On dakika sonra tekrar deneyin.'),
        CarReplyRefusal.failed => t('Yanıt gönderilemedi.'),
      };
}
