# Android Auto

TrackBridge shows incoming APRS messages in Android Auto as **messaging notifications**: the car screen
shows them, reads them aloud and, if you allow it, sends a dictated reply.

## What works

- A message addressed to your callsign appears as a notification on the phone and in the car, with the
  sender's callsign as the name. Android Auto reads it aloud.
- "Okundu" (mark as read) in the car clears it on the phone too, and opening the chat in the app clears
  the car notification.
- **Spoken reply (off by default).** Settings > Android Auto > "Arabadan sesli yanıt". When on, a reply
  dictated in the car is put on the air **without a confirmation dialog**. Limits, enforced in
  `AppController.replyFromCar` (unit tested):
  - only to a station that has messaged you
  - Turkish, Polish and German letters are converted to plain ASCII, everything else is dropped, at most
    67 characters
  - at least 20 s between replies, at most 10 per 10 minutes
  - needs a connected tracker and a real callsign
  - the reason for a refusal is shown to the driver as a notification line that Android Auto reads
- Needs the background service switch (Bağlantı tab) on, so the Bluetooth link stays alive while the
  phone is locked in the car.

## Limits (by design of Android Auto)

- The car only shows messages that arrive **while Android Auto is running**. There is no history in the car.
- Android Auto only supports fixed app categories. A map of arbitrary APRS stations does not fit any of
  them. A "point of interest" list of nearby stations is the only possible route and is **not
  implemented**: it would need the Car App Library, a Google Play developer account (Car App Library apps
  cannot be sideloaded for the car) and Google may refuse it in production.

## Try it

1. Install the APK, grant the notification permission (Ayarlar > Android Auto > "Bildirim iznini kontrol et").
2. Turn on "Arka planda çalış" in the Bağlantı tab and connect the tracker.
3. In the car, or with the Desktop Head Unit (Android Studio > SDK Manager > SDK Tools > Android Auto
   Desktop Head Unit Emulator), let another station message you.
4. For a sideloaded APK, enable Android Auto developer mode (Android Auto settings > tap "Version" 10
   times) and turn on **Unknown sources**; this works for messaging notifications.

## Code

- `android/.../CarMessaging.kt`: builds the `MessagingStyle` notifications (reply action with
  `RemoteInput`, invisible mark-as-read action), keeps the last 5 messages per conversation.
- `android/.../CarMessageReceiver.kt`: receives the reply / mark-as-read actions, no UI.
- `lib/background/native_bridge.dart`: method channel `trackbridge/native` to Dart.
- `lib/state/car_reply.dart`, `lib/core/ascii_text.dart`: reply rules and ASCII conversion.
- `lib/state/message_store.dart`: conversations persisted across restarts.
