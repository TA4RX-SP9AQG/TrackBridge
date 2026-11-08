<div align="center">

# TrackBridge

**A free Android companion app for LoRa APRS trackers. Send and receive APRS messages and position beacons over Bluetooth Low Energy (KISS).**

![Status](https://img.shields.io/badge/status-early%20alpha-orange)
![Platform](https://img.shields.io/badge/platform-Android%207%2B-3DDC84)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

</div>

> **Status: early alpha.** It works on the author's setup (one Heltec Wireless Tracker, one Android phone).
> Expect rough edges. Please report problems as issues, ideally with the tracker model, phone model and Android version.

## Why

Many LoRa APRS trackers (for example the Heltec Wireless Tracker running the
[LoRa APRS Tracker](https://github.com/richonguzman/LoRa_APRS_Tracker) firmware) talk to the phone over
**Bluetooth Low Energy** with the KISS protocol. Classic APRS apps for Android only support Bluetooth *Classic*
(SPP), so they cannot use these devices. TrackBridge speaks the tracker's BLE KISS service directly.

## Features

- Scan for a tracker, connect, automatic reconnect with backoff
- Live list of packets the tracker hears on the radio
- APRS messages: send, receive, delivery state (sent, repeated by a digipeater, acknowledged), automatic `ack`
  for messages addressed to you (rate-limited, can be turned off)
- Position beacon from a fixed position or the phone's GPS, with **APRS position ambiguity** (default about 2 km):
  the hidden digits are never put into the packet
- Visual APRS symbol picker with the real icons, including overlay characters
- **Map of the stations the tracker hears over the radio** (positions in uncompressed, compressed and Mic-E
  format, plus objects and items), drawn with their APRS symbols. Tap a marker for the comment, speed, course,
  altitude, distance and bearing from your position, and how it was heard. A **"Yol tarifi"** button opens
  turn-by-turn navigation to it (Google Maps navigation, any map app, or the web page), and you can send
  that station a message straight from the sheet
- Every transmission is shown as the exact packet and needs your confirmation first

Planned: background operation with message notifications, automatic and SmartBeaconing beacons, a map picker for the fixed position, ready-made messages and reminders for events such as #APRSThursday.

## Tested with

| Part | What |
|---|---|
| Tracker | Heltec Wireless Tracker (ESP32-S3) with the LoRa APRS Tracker firmware, Bluetooth on, **KISS** mode |
| BLE service | `00000001-ba2a-46c9-ae49-01b0961f68bb` (notify `…0003`, write `…0002`) |
| Phone | Android with BLE (minimum Android 7 / API 24) |

Other trackers that expose the same BLE KISS service may work, but are untested.

## Radio and legal notice

Transmitting on amateur radio frequencies requires a valid amateur radio licence and your own callsign. The app
makes the tracker transmit on your behalf; **you are responsible for everything you send.** Packets that reach
APRS-IS are public (for example on aprs.fi) and cannot be taken back. TrackBridge never transmits on its own,
except an acknowledgement for a message addressed to your callsign (setting, on by default, rate-limited).

TrackBridge is an independent project. It is not affiliated with or endorsed by Heltec, the LoRa APRS Tracker
firmware authors, APRSdroid, aprs.fi, or the owners of the APRS name.

## Privacy

No accounts, no analytics, no ads. The only network traffic is **map tiles**, and only after you open the Harita
tab: the tile server (OpenStreetMap by default) sees your IP address and the area you look at. "Yol tarifi" hands
the station's coordinates to the navigation app you choose. Location is read from the phone only if you choose
"phone GPS" as the beacon source, and it leaves the phone only inside a beacon you confirm. The map shows only
what your own tracker heard on the radio; there is no internet (APRS-IS) feed.

## Build

Requirements: Flutter (stable, Dart `^3.12.1`), JDK 17+, Android SDK 37.

```bash
# 1. APRS symbol images are downloaded, not stored in this repository (see assets/symbols/hessu/CREDITS.md)
tools/fetch_symbols.sh            # Windows PowerShell: ./tools/fetch_symbols.ps1

# 2. build and test
flutter pub get
flutter test
flutter build apk --debug
```

`flutter test` and the build fail until step 1 has been run once.

## Project layout

```
lib/core    KISS, AX.25 and APRS encoding/decoding (pure Dart, unit tested with frames captured from a real tracker)
lib/ble     BLE link to the tracker (flutter_reactive_ble)
lib/state   settings, message and packet state
lib/ui      screens and widgets
ble_test    single-page Web Bluetooth tester for debugging a tracker from desktop Chrome
tools       helper scripts
docs        release checklist
```

## Credits

- APRS symbol images: [hessu/aprs-symbols](https://github.com/hessu/aprs-symbols) by Heikki Hannikainen (OH7LZB), the aprs.fi symbol set
- Protocol knowledge: the APRS 1.0.1 specification and the LoRa APRS Tracker firmware by Ricardo Guzman (CA2RXU)
- See [NOTICE.md](NOTICE.md) for third-party components and licences

## License

Code: [GNU General Public License v3.0](LICENSE). Copyright (C) 2026 Erkin Mercan (TA4RX / SP9AQG).

The TrackBridge name and logo (`assets/branding/`, `branding/`) are not covered by the GPL; all rights reserved.
You may use them to refer to this project.

73 de TA4RX / SP9AQG
