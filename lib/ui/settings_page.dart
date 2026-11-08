import 'package:flutter/material.dart';

import '../core/aprs.dart';
import '../core/ax25.dart';
import '../state/app_controller.dart';
import '../core/symbols.dart';
import '../state/models.dart';
import 'beacon_page.dart' show ambiguityLabels;
import 'symbol_picker.dart';
import 'symbol_widget.dart';

/// Parses "52.2297, 21.0122" (as copied from a map app). Returns null if invalid.
({double lat, double lon})? parseLatLon(String text) {
  final parts = text.trim().split(RegExp(r'[\s,;]+')).where((s) => s.isNotEmpty).toList();
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0]);
  final lon = double.tryParse(parts[1]);
  if (lat == null || lon == null || lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  return (lat: lat, lon: lon);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _callsign = TextEditingController();
  final _path = TextEditingController();
  final _comment = TextEditingController();
  final _position = TextEditingController();
  late String _symbolTable;
  late String _symbolCode;
  late int _ambiguity;
  late PositionSource _source;
  late bool _autoAck;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _callsign.text = s.callsign;
    _path.text = s.path;
    _comment.text = s.comment;
    // A stored pair that is not a valid APRS symbol falls back to the default house icon.
    final valid = resolveSymbol(s.symbolTable, s.symbol) != null;
    _symbolTable = valid ? s.symbolTable : '/';
    _symbolCode = valid ? s.symbol : '-';
    _position.text = (s.manualLat != null && s.manualLon != null) ? '${s.manualLat}, ${s.manualLon}' : '';
    _ambiguity = s.ambiguity;
    _source = s.positionSource;
    _autoAck = s.autoAck;
  }

  @override
  void dispose() {
    for (final c in [_callsign, _path, _comment, _position]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickSymbol() async {
    final choice = await Navigator.of(context).push<SymbolChoice>(MaterialPageRoute(
      builder: (_) => SymbolPickerPage(initialTable: _symbolTable, initialCode: _symbolCode),
    ));
    if (choice == null || !mounted) return;
    setState(() {
      _symbolTable = choice.table;
      _symbolCode = choice.code;
    });
  }

  void _fail(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    final callsign = _callsign.text.trim().toUpperCase();
    if (!isUsableCallsign(callsign)) {
      _fail('Geçerli bir çağrı işareti girin (örn. SP9AQG-9). N0CALL kullanılamaz.');
      return;
    }
    final hops = _path.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    try {
      for (final p in hops) {
        Ax25Address.parse(p);
      }
    } on FormatException catch (e) {
      _fail('Yol (path) geçersiz: ${e.message}');
      return;
    }
    if (hops.any((h) => h.contains('*'))) {
      _fail('Yol (path) içinde * kullanılamaz.');
      return;
    }
    if (hops.length > Ax25Frame.maxDigipeaters) {
      _fail('Yol (path) en fazla ${Ax25Frame.maxDigipeaters} adım olabilir (genelde 1-2 yeterli).');
      return;
    }
    final point = _position.text.trim().isEmpty ? null : parseLatLon(_position.text);
    if (_position.text.trim().isNotEmpty && point == null) {
      _fail('Konum "enlem, boylam" biçiminde olmalı (örn. 52.2297, 21.0122).');
      return;
    }
    final comment = _comment.text;
    final asciiOnly = comment.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);
    if (comment.length > kMaxCommentLength || !asciiOnly || comment.contains('|') || comment.contains('~')) {
      _fail('Yorum yalnızca ASCII olmalı (| ve ~ yok) ve en fazla $kMaxCommentLength karakter olabilir.');
      return;
    }
    final current = widget.controller.settings;
    await widget.controller.updateSettings(AppSettings(
      callsign: callsign,
      path: _path.text.trim().toUpperCase(),
      symbolTable: _symbolTable,
      symbol: _symbolCode,
      comment: _comment.text,
      ambiguity: _ambiguity,
      positionSource: _source,
      manualLat: point?.lat,
      manualLon: point?.lon,
      autoAck: _autoAck,
      noticeAccepted: current.noticeAccepted,
      lastDeviceId: current.lastDeviceId,
      lastDeviceName: current.lastDeviceName,
    ));
    if (mounted) _fail('Kaydedildi.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _callsign,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Çağrı işareti-SSID', hintText: 'SP9AQG-9'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _path,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Yol (path)', helperText: 'Virgülle ayırın; boş = digipeater yok'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _comment, decoration: const InputDecoration(labelText: 'Beacon yorumu')),
        const SizedBox(height: 12),
        _SymbolTile(table: _symbolTable, code: _symbolCode, onPick: _pickSymbol),
        const SizedBox(height: 20),
        Text('Beacon konumu', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<PositionSource>(
          segments: const [
            ButtonSegment(value: PositionSource.manual, label: Text('Sabit konum'), icon: Icon(Icons.home)),
            ButtonSegment(value: PositionSource.phone, label: Text('Telefon GPS'), icon: Icon(Icons.my_location)),
          ],
          selected: {_source},
          onSelectionChanged: (v) => setState(() => _source = v.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _position,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(
            labelText: 'Sabit konum (enlem, boylam)',
            helperText: 'Harita uygulamasından kopyalayıp yapıştırabilirsiniz',
          ),
        ),
        const SizedBox(height: 12),
        Text('Konum belirsizliği: $_ambiguity  (${ambiguityLabels[_ambiguity]})'),
        Slider(
          value: _ambiguity.toDouble(),
          min: 0,
          max: 4,
          divisions: 4,
          label: '$_ambiguity',
          onChanged: (v) => setState(() => _ambiguity = v.round()),
        ),
        const Text('0 = tam konum yayınlanır. 2 = yaklaşık 2 km\'lik kare (önerilen).'),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Gelen mesajlara otomatik ack gönder'),
          subtitle: const Text('Yalnızca size adreslenen, numaralı mesajlara karşılık olarak yayın yapar.'),
          value: _autoAck,
          onChanged: (v) => setState(() => _autoAck = v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Kaydet')),
      ]),
    );
  }
}

/// Shows the chosen APRS symbol (image, name, raw characters) and opens the picker.
class _SymbolTile extends StatelessWidget {
  const _SymbolTile({required this.table, required this.code, required this.onPick});

  final String table;
  final String code;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveSymbol(table, code);
    final overlay = resolved?.overlay;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: AprsSymbolIcon(table: table, code: code, size: 44),
        title: Text(resolved?.info.name ?? 'Bilinmeyen sembol'),
        subtitle: Text('Beacon simgesi  ($table$code${overlay == null ? '' : ', katman $overlay'})'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onPick,
      ),
    );
  }
}
