# Release gates

Things that are fine for development and for sideloaded debug builds, but must be resolved before the app is
published in a store.

| Gate | Why | Action |
|---|---|---|
| APRS symbol images | Most hessu symbols have unknown upstream licences; Apple and Kenwood logos are in the set | Remove those symbols or replace the whole `assets/symbols/hessu/` set with a licensed or own set behind the same `lib/core/symbols.dart` catalog |
| Map tiles | The OSM public tile server is not allowed for distributed apps; the app currently defaults to it | Ship with a commercial or self-hosted provider (key handled outside the repo); keep the URL configurable. Offline maps need a provider whose terms allow downloading, or user-supplied MBTiles/PMTiles |
| `INTERNET` permission | Needed for map tiles; declared in the main manifest | Mention it in the store data-safety form (map tiles, no personal data sent) |
| Release signing | Release builds are currently signed with the debug key | Create an upload keystore, keep it out of the repository |
| Tocall | Packets use the firmware's `APLRT1` destination | Request an own APRS tocall |
| Package size | Debug APK is about 180 MB | Build per-ABI release APKs / an app bundle |
| Name, logo, trademarks | Not checked against store listings or trademarks | Check before submitting |
| Store policy text | Radio transmission app | Describe the licence requirement and the confirmation-before-transmit behaviour in the listing |
