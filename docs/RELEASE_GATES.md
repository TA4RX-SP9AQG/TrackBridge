# Release gates

Things that are fine for development and for sideloaded debug builds, but must be resolved before the app is
published in a store.

| Gate | Why | Action |
|---|---|---|
| APRS symbol images | Most hessu symbols have unknown upstream licences; Apple and Kenwood logos are in the set | Remove those symbols or replace the whole `assets/symbols/hessu/` set with a licensed or own set behind the same `lib/core/symbols.dart` catalog |
| Map tiles (when the map is added) | The OSM public tile server forbids shipped apps | Configure a commercial or self-hosted provider; never hard-code the OSM URL |
| `INTERNET` permission | Only the debug manifest has it today | Add it to the main manifest when tiles or any network feature is added |
| Release signing | Release builds are currently signed with the debug key | Create an upload keystore, keep it out of the repository |
| Tocall | Packets use the firmware's `APLRT1` destination | Request an own APRS tocall |
| Package size | Debug APK is about 180 MB | Build per-ABI release APKs / an app bundle |
| Name, logo, trademarks | Not checked against store listings or trademarks | Check before submitting |
| Store policy text | Radio transmission app | Describe the licence requirement and the confirmation-before-transmit behaviour in the listing |
