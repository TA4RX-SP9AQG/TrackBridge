# APRS symbol images

The symbol images in this folder are from **aprs-symbols** by Heikki Hannikainen (OH7LZB),
the symbol set used by aprs.fi: https://github.com/hessu/aprs-symbols/

The author allows free use in APRS applications and asks that the source is credited.
The copyright status differs per symbol; see `COPYRIGHT_UPSTREAM.md` (copied unchanged from
the upstream repository).

**Release gate:** many symbols are marked "Licensing: Unknown" upstream, and the set includes
brand logos (Apple, Kenwood). Before any store build, remove or replace those symbols or replace
this whole folder with a licensed/own set. See docs/RELEASE_GATES.md.

Files (all sheets are 16 columns x 6 rows of 128 px tiles, tile index = character code - 0x21):
- aprs-symbols-128-0.png: primary table ('/')
- aprs-symbols-128-1.png: alternate table ('\')
- aprs-symbols-128-2.png: overlay characters 0-9 A-Z, drawn on top of an alternate-table symbol
