/// OpenStreetMap standard tiles. **Development use only**: the public OSM tile
/// server is not meant for distributed apps (see docs/RELEASE_GATES.md).
const String kDefaultTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// True for an https URL template that contains the `{z}`, `{x}` and `{y}` placeholders.
bool isValidTileUrl(String value) {
  final text = value.trim();
  if (!text.startsWith('https://')) return false;
  if (!text.contains('{z}') || !text.contains('{x}') || !text.contains('{y}')) return false;
  if (text.contains(' ')) return false;
  final host = tileHost(text);
  return host != null && host.isNotEmpty && host.contains('.');
}

/// The host part of a tile URL template (placeholders such as `{s}` kept), or null.
String? tileHost(String value) {
  final text = value.trim();
  const prefix = 'https://';
  if (!text.startsWith(prefix)) return null;
  final rest = text.substring(prefix.length);
  final end = rest.indexOf('/');
  return end < 0 ? rest : rest.substring(0, end);
}

bool isOpenStreetMapUrl(String value) => (tileHost(value) ?? '').endsWith('openstreetmap.org');
