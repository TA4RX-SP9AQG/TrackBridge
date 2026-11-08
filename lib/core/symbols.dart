/// APRS symbol catalog: names and categories for the primary (`/`) and
/// alternate (`\`) tables, plus the table-character / overlay rules.
///
/// Names and categories are written for this app from the APRS 1.0.1
/// specification. The images live in the sprite sheets (see `ui/symbol_widget.dart`).
library;

enum SymbolCategory {
  stations('Telsiz ve istasyonlar'),
  vehicles('Araçlar'),
  people('Kişiler ve hayvanlar'),
  emergency('Acil durum ve hizmetler'),
  weather('Hava durumu'),
  places('Yerler ve işaretler'),
  other('Diğer');

  const SymbolCategory(this.label);

  final String label;
}

class SymbolInfo {
  const SymbolInfo({
    required this.table,
    required this.code,
    required this.name,
    required this.category,
    this.acceptsOverlay = false,
  });

  /// `/` (primary) or `\` (alternate).
  final String table;

  /// Symbol code character, 0x21-0x7E.
  final String code;
  final String name;
  final SymbolCategory category;

  /// True for alternate-table symbols that are normally shown with an overlay
  /// character (0-9, A-Z).
  final bool acceptsOverlay;

  bool get reserved => name == _reserved;
}

/// A symbol resolved from a table character and a code.
class ResolvedSymbol {
  const ResolvedSymbol(this.info, this.overlay);

  final SymbolInfo info;

  /// Overlay character drawn on top, or null.
  final String? overlay;
}

const String _reserved = 'Reserved';
const String _primaryTable = '/';
const String _alternateTable = r'\';

typedef _Entry = (String name, SymbolCategory category);

const _Entry _res = (_reserved, SymbolCategory.other);

const SymbolCategory _st = SymbolCategory.stations;
const SymbolCategory _ve = SymbolCategory.vehicles;
const SymbolCategory _pe = SymbolCategory.people;
const SymbolCategory _em = SymbolCategory.emergency;
const SymbolCategory _wx = SymbolCategory.weather;
const SymbolCategory _pl = SymbolCategory.places;
const SymbolCategory _ot = SymbolCategory.other;

const Map<String, _Entry> _primary = {
  '!': ('Police / Sheriff', _em),
  '"': _res,
  '#': ('Digipeater', _st),
  r'$': ('Telephone', _st),
  '%': ('DX cluster', _st),
  '&': ('HF gateway', _st),
  "'": ('Small aircraft', _ve),
  '(': ('Mobile satellite station', _ve),
  ')': ('Wheelchair / accessible', _pl),
  '*': ('Snowmobile', _ve),
  '+': ('Red Cross', _em),
  ',': ('Scouts', _pe),
  '-': ('House (VHF)', _st),
  '.': ('X marker', _pl),
  '/': ('Red dot', _pl),
  '0': ('Numbered circle 0', _pl),
  '1': ('Numbered circle 1', _pl),
  '2': ('Numbered circle 2', _pl),
  '3': ('Numbered circle 3', _pl),
  '4': ('Numbered circle 4', _pl),
  '5': ('Numbered circle 5', _pl),
  '6': ('Numbered circle 6', _pl),
  '7': ('Numbered circle 7', _pl),
  '8': ('Numbered circle 8', _pl),
  '9': ('Numbered circle 9', _pl),
  ':': ('Fire', _em),
  ';': ('Campground', _pl),
  '<': ('Motorcycle', _ve),
  '=': ('Railroad engine', _ve),
  '>': ('Car', _ve),
  '?': ('File server', _st),
  '@': ('Hurricane / tropical storm', _wx),
  'A': ('Aid station', _em),
  'B': ('BBS', _st),
  'C': ('Canoe', _ve),
  'D': _res,
  'E': ('Eyeball (event)', _pl),
  'F': ('Farm vehicle / tractor', _ve),
  'G': ('Grid square', _pl),
  'H': ('Hotel', _pl),
  'I': ('TCP/IP node', _st),
  'J': _res,
  'K': ('School', _pl),
  'L': ('PC user', _st),
  'M': ('MacAPRS', _st),
  'N': ('NTS station', _st),
  'O': ('Balloon', _ve),
  'P': ('Police', _em),
  'Q': _res,
  'R': ('Recreational vehicle', _ve),
  'S': ('Space shuttle', _ve),
  'T': ('SSTV', _st),
  'U': ('Bus', _ve),
  'V': ('ATV', _st),
  'W': ('National weather service site', _wx),
  'X': ('Helicopter', _ve),
  'Y': ('Sailboat / yacht', _ve),
  'Z': ('WinAPRS', _st),
  '[': ('Jogger / person on foot', _pe),
  r'\': ('Triangle (DF station)', _st),
  ']': ('PBBS mailbox', _st),
  '^': ('Large aircraft', _ve),
  '_': ('Weather station', _wx),
  '`': ('Dish antenna', _st),
  'a': ('Ambulance', _em),
  'b': ('Bicycle', _ve),
  'c': ('Incident command post', _em),
  'd': ('Fire department', _em),
  'e': ('Horse', _pe),
  'f': ('Fire truck', _em),
  'g': ('Glider', _ve),
  'h': ('Hospital', _em),
  'i': ('IOTA (islands on the air)', _pl),
  'j': ('Jeep', _ve),
  'k': ('Truck', _ve),
  'l': ('Laptop', _st),
  'm': ('Mic-E repeater', _st),
  'n': ('Node', _st),
  'o': ('Emergency operations center', _em),
  'p': ('Dog / rover', _pe),
  'q': ('Grid square (2x2)', _pl),
  'r': ('Repeater', _st),
  's': ('Ship / power boat', _ve),
  't': ('Truck stop', _pl),
  'u': ('Truck (18 wheeler)', _ve),
  'v': ('Van', _ve),
  'w': ('Water station', _em),
  'x': ('X-APRS', _st),
  'y': ('House with yagi antenna', _st),
  'z': ('Shelter', _em),
  '{': _res,
  '|': ('TNC stream switch', _ot),
  '}': _res,
  '~': ('TNC stream switch (2)', _ot),
};

const Map<String, _Entry> _alternate = {
  '!': ('Emergency', _em),
  '"': _res,
  '#': ('Digipeater (overlay)', _st),
  r'$': ('Bank / ATM', _pl),
  '%': _res,
  '&': ('Gateway (overlay: I = igate)', _st),
  "'": ('Crash site', _em),
  '(': ('Cloudy', _wx),
  ')': ('Mobile emergency operations', _em),
  '*': ('Snow', _wx),
  '+': ('Church', _pl),
  ',': ('Girl Scouts', _pe),
  '-': ('House (HF)', _st),
  '.': ('Unknown / question mark', _ot),
  '/': ('Waypoint destination', _pl),
  '0': ('Circle (overlay)', _st),
  '1': _res,
  '2': _res,
  '3': _res,
  '4': _res,
  '5': _res,
  '6': _res,
  '7': _res,
  '8': _res,
  '9': ('Gas station', _pl),
  ':': ('Hail', _wx),
  ';': ('Park / picnic area', _pl),
  '<': ('Weather advisory', _wx),
  '=': _res,
  '>': ('Car (overlay)', _ve),
  '?': ('Information kiosk', _pl),
  '@': ('Hurricane', _wx),
  'A': ('Box (overlay)', _st),
  'B': ('Blowing snow', _wx),
  'C': ('Coast guard', _em),
  'D': ('Drizzle', _wx),
  'E': ('Smoke', _wx),
  'F': ('Freezing rain', _wx),
  'G': ('Snow shower', _wx),
  'H': ('Haze', _wx),
  'I': ('Rain shower', _wx),
  'J': ('Lightning', _wx),
  'K': ('Kenwood', _st),
  'L': ('Lighthouse', _pl),
  'M': _res,
  'N': ('Navigation buoy', _pl),
  'O': ('Rocket', _ve),
  'P': ('Parking', _pl),
  'Q': ('Earthquake', _wx),
  'R': ('Restaurant', _pl),
  'S': ('Satellite', _ve),
  'T': ('Thunderstorm', _wx),
  'U': ('Sunny', _wx),
  'V': ('VORTAC navigation aid', _pl),
  'W': ('National weather service site', _wx),
  'X': ('Pharmacy', _pl),
  'Y': ('Radios / devices', _st),
  'Z': _res,
  '[': ('Wall cloud', _wx),
  r'\': _res,
  ']': _res,
  '^': ('Aircraft (overlay)', _ve),
  '_': ('Weather station (overlay)', _wx),
  '`': ('Rain', _wx),
  'a': ('ARRL / ARES / Winlink / D-STAR', _st),
  'b': ('Blowing dust / sand', _wx),
  'c': ('Civil defense', _em),
  'd': ('DX spot', _st),
  'e': ('Sleet', _wx),
  'f': ('Funnel cloud', _wx),
  'g': ('Gale', _wx),
  'h': ('Ham store', _pl),
  'i': ('Point of interest (overlay)', _pl),
  'j': ('Work zone', _pl),
  'k': ('Special vehicle (overlay)', _ve),
  'l': ('Area marker', _pl),
  'm': ('Value sign', _pl),
  'n': ('Triangle (overlay)', _pl),
  'o': ('Small circle', _pl),
  'p': ('Partly cloudy', _wx),
  'q': _res,
  'r': ('Restrooms', _pl),
  's': ('Ship / boat (overlay)', _ve),
  't': ('Tornado', _wx),
  'u': ('Truck (overlay)', _ve),
  'v': ('Van (overlay)', _ve),
  'w': ('Flooding', _wx),
  'x': _res,
  'y': ('Skywarn', _em),
  'z': ('Shelter (overlay)', _em),
  '{': ('Fog', _wx),
  '|': _res,
  '}': _res,
  '~': _res,
};

/// Alternate-table symbols that are normally used with an overlay character.
const Set<String> _overlayCapable = {'#', '&', '0', '>', 'A', '^', '_', 'a', 'c', 'i', 'k', 'n', 's', 'u', 'v', 'z'};

List<SymbolInfo> _build(String table, Map<String, _Entry> entries) => List<SymbolInfo>.unmodifiable([
      for (final e in entries.entries)
        SymbolInfo(
          table: table,
          code: e.key,
          name: e.value.$1,
          category: e.value.$2,
          acceptsOverlay: table == _alternateTable && _overlayCapable.contains(e.key),
        ),
    ]);

final List<SymbolInfo> primarySymbols = _build(_primaryTable, _primary);
final List<SymbolInfo> alternateSymbols = _build(_alternateTable, _alternate);

final RegExp _overlayPattern = RegExp(r'^[0-9A-Z]$');

bool isOverlayChar(String c) => _overlayPattern.hasMatch(c);

/// Valid APRS "symbol table identifier": `/`, `\`, or an overlay character.
bool tableCharIsValid(String c) => c == _primaryTable || c == _alternateTable || isOverlayChar(c);

/// Looks up a symbol by its real table (`/` primary, anything else alternate).
SymbolInfo? lookupSymbol(String table, String code) {
  if (code.length != 1) return null;
  final unit = code.codeUnitAt(0);
  if (unit < 0x21 || unit > 0x7E) return null;
  final map = table == _primaryTable ? _primary : _alternate;
  final entry = map[code];
  if (entry == null) return null;
  return SymbolInfo(
    table: table == _primaryTable ? _primaryTable : _alternateTable,
    code: code,
    name: entry.$1,
    category: entry.$2,
    acceptsOverlay: table != _primaryTable && _overlayCapable.contains(code),
  );
}

/// Resolves the pair stored in a position packet (table character + code).
/// A digit or capital letter as table character means alternate table with
/// that overlay. Returns null for invalid input.
ResolvedSymbol? resolveSymbol(String tableChar, String code) {
  if (!tableCharIsValid(tableChar)) return null;
  final real = tableChar == _primaryTable ? _primaryTable : _alternateTable;
  final info = lookupSymbol(real, code);
  if (info == null) return null;
  return ResolvedSymbol(info, isOverlayChar(tableChar) ? tableChar : null);
}

/// Column and row of a code in a 16 x 6 sprite sheet, or null if out of range.
({int col, int row})? spriteCell(String code) {
  if (code.length != 1) return null;
  final index = code.codeUnitAt(0) - 0x21;
  if (index < 0 || index > 93) return null;
  return (col: index % 16, row: index ~/ 16);
}

/// Symbols a user can pick (reserved entries removed).
List<SymbolInfo> selectableSymbols(List<SymbolInfo> table) =>
    table.where((s) => !s.reserved).toList(growable: false);

/// Filters [table] by a case-insensitive query on name or code, optionally
/// limited to a [category]. Reserved entries never match.
List<SymbolInfo> searchSymbols(List<SymbolInfo> table, String query, {SymbolCategory? category}) {
  final q = query.trim().toLowerCase();
  return selectableSymbols(table)
      .where((s) => category == null || s.category == category)
      .where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.code.toLowerCase() == q)
      .toList(growable: false);
}
