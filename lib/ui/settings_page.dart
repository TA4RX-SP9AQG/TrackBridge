import 'package:flutter/material.dart';

import '../core/aprs.dart';
import '../core/ax25.dart';
import '../core/symbols.dart';
import '../core/tile_url.dart';
import '../state/app_controller.dart';
import '../state/models.dart';
import 'app_theme.dart';
import 'beacon_page.dart' show ambiguityLabels;
import '../state/wavelog_client.dart';
import 'permissions.dart';
import 'symbol_picker.dart';
import 'symbol_widget.dart';
import 'widgets/ui_kit.dart';
import '../l10n/app_strings.dart';

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
  const SettingsPage({super.key, required this.controller, this.requestNotificationPermission});

  final AppController controller;

  /// Asks for the notification permission; replaced in tests.
  final Future<bool> Function()? requestNotificationPermission;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _callsign = TextEditingController();
  final _path = TextEditingController();
  final _comment = TextEditingController();
  final _trackerCall = TextEditingController();
  final _tileUrl = TextEditingController();
  final _position = TextEditingController();
  final _wlUrl = TextEditingController();
  final _wlKey = TextEditingController();
  final _wlProfile = TextEditingController();
  final _wlFreq = TextEditingController();
  late String _symbolTable;
  late String _symbolCode;
  late int _ambiguity;
  late PositionSource _source;
  late bool _autoAck;
  late bool _carVoiceReply;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _callsign.text = s.callsign;
    _path.text = s.path;
    _comment.text = s.comment;
    _trackerCall.text = s.trackerCallsign;
    _tileUrl.text = s.tileUrl;
    _wlUrl.text = s.wavelogUrl;
    _wlKey.text = s.wavelogKey;
    _wlProfile.text = s.wavelogProfileId;
    _wlFreq.text = s.wavelogFreqMhz.toString();
    // A stored pair that is not a valid APRS symbol falls back to the default house icon.
    final valid = resolveSymbol(s.symbolTable, s.symbol) != null;
    _symbolTable = valid ? s.symbolTable : '/';
    _symbolCode = valid ? s.symbol : '-';
    _position.text = (s.manualLat != null && s.manualLon != null) ? '${s.manualLat}, ${s.manualLon}' : '';
    _ambiguity = s.ambiguity;
    _source = s.positionSource;
    _autoAck = s.autoAck;
    _carVoiceReply = s.carVoiceReply;
  }

  @override
  void dispose() {
    for (final c in [_callsign, _path, _comment, _trackerCall, _position, _tileUrl, _wlUrl, _wlKey, _wlProfile, _wlFreq]) {
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
    // A discrete choice is applied right away; only the text fields need "Kaydet".
    // Built from the saved settings so other unsaved form edits are not written by accident.
    final c = widget.controller;
    await c.updateSettings(c.settings.copyWith(symbolTable: choice.table, symbol: choice.code));
  }

  Future<void> _applyNow(AppSettings Function(AppSettings saved) change) {
    final c = widget.controller;
    return c.updateSettings(change(c.settings));
  }

  Future<void> _testWavelog() async {
    final config = WavelogConfig(
      url: _wlUrl.text,
      apiKey: _wlKey.text,
      stationProfileId: _wlProfile.text,
      freqMhz: double.tryParse(_wlFreq.text.trim().replaceAll(',', '.')) ?? 0,
    );
    _fail(t('Bağlantı deneniyor...'));
    final result = await widget.controller.wavelog.testConnection(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _fail(result.message);
  }

  Future<void> _checkNotifications() async {
    final granted = await (widget.requestNotificationPermission ?? ensureNotificationPermission)();
    if (!mounted) return;
    _fail(granted ? t('Bildirim izni verildi.') : t('Bildirim izni verilmedi. Android ayarlarından TrackBridge için bildirimleri açın.'));
  }

  void _fail(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    final callsign = _callsign.text.trim().toUpperCase();
    if (!isUsableCallsign(callsign)) {
      _fail(t('Geçerli bir çağrı işareti girin (örn. SP9AQG-9). N0CALL kullanılamaz.'));
      return;
    }
    final trackerCall = _trackerCall.text.trim().toUpperCase();
    if (trackerCall.isNotEmpty && !isUsableCallsign(trackerCall)) {
      _fail(t('Tracker çağrı işareti geçersiz (örn. SP9AQG-7).'));
      return;
    }
    final hops = _path.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    try {
      for (final p in hops) {
        Ax25Address.parse(p);
      }
    } on FormatException catch (e) {
      _fail(t('Yol (path) geçersiz: {v1}', {'v1': e.message}));
      return;
    }
    if (hops.any((h) => h.contains('*'))) {
      _fail(t('Yol (path) içinde * kullanılamaz.'));
      return;
    }
    if (hops.length > Ax25Frame.maxDigipeaters) {
      _fail(t('Yol (path) en fazla {v1} adım olabilir (genelde 1-2 yeterli).', {'v1': Ax25Frame.maxDigipeaters}));
      return;
    }
    final point = _position.text.trim().isEmpty ? null : parseLatLon(_position.text);
    if (_position.text.trim().isNotEmpty && point == null) {
      _fail(t('Konum "enlem, boylam" biçiminde olmalı (örn. 52.2297, 21.0122).'));
      return;
    }
    final comment = _comment.text;
    final asciiOnly = comment.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);
    if (comment.length > kMaxCommentLength || !asciiOnly || comment.contains('|') || comment.contains('~')) {
      _fail(t('Yorum yalnızca ASCII olmalı (| ve ~ yok) ve en fazla {kMaxCommentLength} karakter olabilir.', {'kMaxCommentLength': kMaxCommentLength}));
      return;
    }
    final tileUrl = _tileUrl.text.trim();
    if (!isValidTileUrl(tileUrl)) {
      _fail(t('Harita karo adresi https:// ile başlamalı ve {z}, {x}, {y} içermeli.'));
      return;
    }
    final wlUrl = _wlUrl.text.trim();
    final wlProfile = _wlProfile.text.trim();
    final wlFreq = double.tryParse(_wlFreq.text.trim().replaceAll(',', '.'));
    final wlTouched = wlUrl.isNotEmpty || _wlKey.text.trim().isNotEmpty || wlProfile.isNotEmpty;
    if (wlTouched) {
      final problem = WavelogConfig.urlProblem(wlUrl);
      if (problem != null) {
        _fail(t('Wavelog: {problem}', {'problem': problem}));
        return;
      }
      if (int.tryParse(wlProfile) == null) {
        _fail(t('Wavelog istasyon profil numarası bir sayı olmalı.'));
        return;
      }
    }
    if (wlFreq == null || wlFreq <= 0) {
      _fail(t('Wavelog frekansı MHz olarak girilmeli (örn. 433.775).'));
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
      trackerCallsign: trackerCall,
      manualLat: point?.lat,
      manualLon: point?.lon,
      autoAck: _autoAck,
      carVoiceReply: _carVoiceReply,
      wavelogUrl: wlUrl,
      wavelogKey: _wlKey.text.trim(),
      wavelogProfileId: wlProfile,
      wavelogFreqMhz: wlFreq,
      noticeAccepted: current.noticeAccepted,
      lastDeviceId: current.lastDeviceId,
      lastDeviceName: current.lastDeviceName,
      tileUrl: tileUrl,
      language: current.language,
    ));
    if (mounted) _fail(t('Kaydedildi.'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('Ayarlar'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(Gaps.l, 0, Gaps.l, Gaps.xl), children: [
        SectionHeader(t('İstasyon'), subtitle: t('Paketlerde görünen kimliğiniz')),
        SurfaceCard(
          child: Column(children: [
            TextField(
              controller: _callsign,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: t('Çağrı işareti-SSID'), hintText: t('SP9AQG-9')),
            ),
            const SizedBox(height: Gaps.l),
            TextField(
              controller: _path,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: t('Yol (path)'), helperText: t('Virgülle ayırın; boş = digipeater yok')),
            ),
          ]),
        ),
        SectionHeader(t('Beacon'), subtitle: t('Konum paketinizin görünümü ve konumu')),
        _SymbolTile(table: _symbolTable, code: _symbolCode, onPick: _pickSymbol),
        const SizedBox(height: Gaps.m),
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _comment, decoration: InputDecoration(labelText: t('Beacon yorumu'))),
            const SizedBox(height: Gaps.xl),
            Text(t('Beacon konumu'), style: theme.textTheme.titleSmall),
            const SizedBox(height: Gaps.s),
            RadioGroup<PositionSource>(
              groupValue: _source,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _source = v);
                _applyNow((s) => s.copyWith(positionSource: v));
              },
              child: Column(children: [
                RadioListTile<PositionSource>(
                  contentPadding: EdgeInsets.zero,
                  value: PositionSource.manual,
                  title: Text(t('Sabit konum')),
                  secondary: const Icon(Icons.home_outlined),
                ),
                RadioListTile<PositionSource>(
                  contentPadding: EdgeInsets.zero,
                  value: PositionSource.phone,
                  title: Text(t('Telefon GPS')),
                  secondary: const Icon(Icons.my_location_rounded),
                ),
                RadioListTile<PositionSource>(
                  contentPadding: EdgeInsets.zero,
                  value: PositionSource.tracker,
                  title: Text(t('Tracker GPS')),
                  subtitle: Text(t('Cihazın kendi GPS modülü varsa (dahili ya da bağlı)')),
                  secondary: const Icon(Icons.memory_rounded),
                ),
              ]),
            ),
            if (_source == PositionSource.tracker) ...[
              const SizedBox(height: Gaps.s),
              TextField(
                controller: _trackerCall,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('Tracker çağrı işareti (boşsa yukarıdaki)'),
                  hintText: t('SP9AQG-9'),
                  helperText: t('Tracker kendi GPS konumuyla beacon atar ve bunu telefona da iletir; uygulama konumu oradan okur. Tracker aynı konumu zaten yayınlıyorsa uygulamadan ayrıca beacon atmak onu iki kez yayınlar.'),
                  helperMaxLines: 5,
                ),
              ),
            ],
            const SizedBox(height: Gaps.l),
            TextField(
              controller: _position,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: t('Sabit konum (enlem, boylam)'),
                helperText: t('Harita uygulamasından kopyalayıp yapıştırabilirsiniz'),
              ),
            ),
            const SizedBox(height: Gaps.xl),
            Row(children: [
              Expanded(child: Text(t('Konum belirsizliği'), style: theme.textTheme.titleSmall)),
              StatusPill(
                '$_ambiguity  (${ambiguityLabels[_ambiguity]})',
                tone: _ambiguity == 0 ? PillTone.warning : PillTone.success,
              ),
            ]),
            Slider(
              value: _ambiguity.toDouble(),
              min: 0,
              max: 4,
              divisions: 4,
              label: '$_ambiguity',
              onChanged: (v) => setState(() => _ambiguity = v.round()),
              onChangeEnd: (v) => _applyNow((s) => s.copyWith(ambiguity: v.round())),
            ),
            Text(
              t('0 = tam konum yayınlanır. 2 = yaklaşık 2 km\'lik kare (önerilen).'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
        SectionHeader(t('Mesajlar')),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.l, vertical: Gaps.xs),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('Gelen mesajlara otomatik ack gönder')),
            subtitle: Text(t('Yalnızca size adreslenen, numaralı mesajlara karşılık olarak yayın yapar.')),
            value: _autoAck,
            onChanged: (v) {
              setState(() => _autoAck = v);
              _applyNow((s) => s.copyWith(autoAck: v));
            },
          ),
        ),
        SectionHeader(t('Android Auto'), subtitle: t('Arabada mesajlar sesli okunur')),
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              t('Arabanın Android Auto ekranı size gelen APRS mesajlarını bildirim olarak gösterir ve sesli okur. Yalnızca Android Auto açıkken gelen mesajlar görünür; geçmiş mesajlar yalnızca uygulamada kalır.'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Gaps.m),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('Arabadan sesli yanıt')),
              subtitle: Text(
                t('Açıkken, arabada dikte ettiğiniz yanıt telsizle yayınlanır ve onay penceresi olmadan gider. Yalnızca size mesaj atan istasyona, en fazla 67 karakter, Türkçe harfler sade ASCII harflere çevrilerek, 20 sn arayla gönderilir. Yayından siz sorumlusunuz.'),
              ),
              value: _carVoiceReply,
              onChanged: (v) {
                setState(() => _carVoiceReply = v);
                _applyNow((s) => s.copyWith(carVoiceReply: v));
              },
            ),
            const SizedBox(height: Gaps.s),
            OutlinedButton.icon(
              onPressed: _checkNotifications,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(t('Bildirim iznini kontrol et')),
            ),
          ]),
        ),
        SectionHeader(t('Wavelog'), subtitle: t('Mesajlaşmaları günlüğünüze QSO olarak kaydedin (isteğe bağlı)')),
        SurfaceCard(
          child: Column(children: [
            TextField(
              controller: _wlUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: t('Wavelog adresi'), hintText: t('https://log.ornek.com')),
            ),
            const SizedBox(height: Gaps.l),
            TextField(
              controller: _wlKey,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t('API anahtarı (okuma+yazma)'),
                helperText: t('Yalnızca bu telefonda saklanır; yalnızca siz "Wavelog\'a kaydet" dediğinizde kullanılır.'),
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: Gaps.l),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _wlProfile,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t('İstasyon profil no')),
                ),
              ),
              const SizedBox(width: Gaps.m),
              Expanded(
                child: TextField(
                  controller: _wlFreq,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: t('Frekans (MHz)')),
                ),
              ),
            ]),
            const SizedBox(height: Gaps.l),
            OutlinedButton.icon(
              onPressed: _testWavelog,
              icon: const Icon(Icons.wifi_tethering_rounded),
              label: Text(t('Bağlantıyı dene')),
            ),
          ]),
        ),
        SectionHeader(t('Harita')),
        SurfaceCard(
          child: TextField(
            controller: _tileUrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: t('Harita karo adresi'),
              helperText: t('Varsayılan OpenStreetMap yalnızca geliştirme/test içindir. {z}/{x}/{y} gerekir.'),
              helperMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: t('Varsayılana dön'),
                icon: const Icon(Icons.restore_rounded),
                onPressed: () => setState(() => _tileUrl.text = kDefaultTileUrl),
              ),
            ),
          ),
        ),
        SectionHeader(t('Dil')),
        SurfaceCard(
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'system', label: Text(t('Telefon dili'))),
              const ButtonSegment(value: 'tr', label: Text('Türkçe')),
              const ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {widget.controller.settings.language},
            onSelectionChanged: (v) => _applyNow((saved) => saved.copyWith(language: v.first)),
          ),
        ),
        SectionHeader(t('Hakkında')),
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('TrackBridge'), style: theme.textTheme.titleSmall),
            const SizedBox(height: Gaps.xs),
            Text(
              t('Açık kaynak (GPL-3.0). APRS simgeleri: hessu/aprs-symbols (OH7LZB). Harita verisi © OpenStreetMap katkıda bulunanlar.'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
      bottomNavigationBar: Material(
        color: scheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.l, Gaps.s, Gaps.l, Gaps.s),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(t('Kaydet')),
            ),
          ),
        ),
      ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resolved = resolveSymbol(table, code);
    final overlay = resolved?.overlay;
    return SurfaceCard(
      onTap: onPick,
      child: Row(children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.m)),
          alignment: Alignment.center,
          child: AprsSymbolIcon(table: table, code: code, size: 44),
        ),
        const SizedBox(width: Gaps.l),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(resolved?.info.name ?? t('Bilinmeyen sembol'), style: theme.textTheme.titleMedium),
            Text(
              t('Beacon simgesi  ({table}{code}{v1})', {'table': table, 'code': code, 'v1': overlay == null ? '' : t(', katman {overlay}', {'overlay': overlay})}),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      ]),
    );
  }
}
