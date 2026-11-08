# Third-party components

TrackBridge itself is licensed under the GNU General Public License v3.0 (see `LICENSE`).
The components below keep their own licences.

## Direct dependencies (Dart/Flutter packages, as resolved in `pubspec.lock`)

| Package | Licence |
|---|---|
| flutter_reactive_ble | BSD (Signify Holding) |
| permission_handler | MIT (Baseflow) |
| geolocator | MIT (Baseflow) |
| flutter_map | BSD-3-Clause |
| latlong2 | Apache-2.0 |
| url_launcher | BSD-3-Clause (The Flutter Authors) |
| shared_preferences | BSD-3-Clause (The Flutter Authors) |
| device_info_plus | BSD-3-Clause (The Chromium Authors) |
| cupertino_icons | MIT |
| flutter_launcher_icons (dev only) | MIT |

Transitive dependencies are covered by their own licences; the app shows them through Flutter's built-in
licence page mechanism when built.

## APRS symbol images (not included in this repository)

`tools/fetch_symbols.sh` downloads the sprite sheets from
[hessu/aprs-symbols](https://github.com/hessu/aprs-symbols) (Heikki Hannikainen, OH7LZB) at a pinned commit.
The author allows free use in APRS applications and asks that the source is credited. The copyright status
differs per symbol: many are marked "Licensing: Unknown" upstream and the set contains brand logos. The images
are therefore not redistributed here, and a store build must replace or prune them (see `docs/RELEASE_GATES.md`).

## Protocols and prior work

The KISS, AX.25 and APRS code in `lib/core` was written for this project from the public specifications
(KISS TNC protocol, AX.25 UI frames, APRS 1.0.1) and verified against frames captured from a real tracker. The
BLE service layout comes from observing the LoRa APRS Tracker firmware
([richonguzman/LoRa_APRS_Tracker](https://github.com/richonguzman/LoRa_APRS_Tracker), GPL-3.0); no firmware
source code is copied.

## Map data

Map tiles come from a tile server configured in Settings. The default is the OpenStreetMap public tile server,
which is only suitable for development and personal testing under its
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/) (valid User-Agent, attribution, no bulk
or offline downloading). Map data © OpenStreetMap contributors (ODbL).

## Branding

The TrackBridge name and logo (`assets/branding/`, `branding/`) are not covered by the GPL.
All rights reserved by the author.
