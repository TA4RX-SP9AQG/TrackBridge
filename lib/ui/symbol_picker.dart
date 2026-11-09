import 'package:flutter/material.dart';

import '../core/symbols.dart';
import 'symbol_widget.dart';
import '../l10n/app_strings.dart';

/// The value stored in settings and sent in position packets: the table
/// character (`/`, `\` or an overlay character) and the symbol code.
class SymbolChoice {
  const SymbolChoice(this.table, this.code);

  final String table;
  final String code;
}

/// Full screen picker with the real symbol images. Pops a [SymbolChoice], or
/// null when the user goes back.
class SymbolPickerPage extends StatefulWidget {
  const SymbolPickerPage({super.key, required this.initialTable, required this.initialCode});

  final String initialTable;
  final String initialCode;

  @override
  State<SymbolPickerPage> createState() => _SymbolPickerPageState();
}

class _SymbolPickerPageState extends State<SymbolPickerPage> {
  late bool _alternate;
  SymbolCategory? _category;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _alternate = widget.initialTable != '/';
  }

  List<SymbolInfo> get _visible =>
      searchSymbols(_alternate ? alternateSymbols : primarySymbols, _query, category: _category);

  Future<void> _select(SymbolInfo symbol) async {
    if (!symbol.acceptsOverlay) {
      Navigator.of(context).pop(SymbolChoice(symbol.table, symbol.code));
      return;
    }
    final overlay = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _OverlaySheet(symbol: symbol),
    );
    if (overlay == null || !mounted) return;
    // "none" is reported as the backslash itself.
    Navigator.of(context).pop(SymbolChoice(overlay, symbol.code));
  }

  @override
  Widget build(BuildContext context) {
    final symbols = _visible;
    return Scaffold(
      appBar: AppBar(title: Text(t('Sembol seç'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(t('Birincil'))),
              ButtonSegment(value: true, label: Text(t('Alternatif'))),
            ],
            selected: {_alternate},
            onSelectionChanged: (v) => setState(() => _alternate = v.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: t('Ara (İngilizce ad ya da karakter)'),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                  label: Text(t('Tümü')),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
              ),
              for (final c in SymbolCategory.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = _category == c ? null : c),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: symbols.isEmpty
              ? Center(child: Text(t('Eşleşen sembol yok')))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 96,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: symbols.length,
                  itemBuilder: (context, i) => _SymbolTile(
                    symbol: symbols[i],
                    selected: _isCurrent(symbols[i]),
                    onTap: () => _select(symbols[i]),
                  ),
                ),
        ),
      ]),
    );
  }

  bool _isCurrent(SymbolInfo s) {
    final current = resolveSymbol(widget.initialTable, widget.initialCode);
    return current != null && current.info.table == s.table && current.info.code == s.code;
  }
}

class _SymbolTile extends StatelessWidget {
  const _SymbolTile({required this.symbol, required this.selected, required this.onTap});

  final SymbolInfo symbol;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '${symbol.name}  (${symbol.table}${symbol.code})',
      child: InkWell(
        key: ValueKey('symbol_${symbol.table}${symbol.code}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            AprsSymbolIcon(table: symbol.table, code: symbol.code, size: 48),
            const SizedBox(height: 2),
            Expanded(
              child: Text(
                symbol.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OverlaySheet extends StatelessWidget {
  const _OverlaySheet({required this.symbol});

  final SymbolInfo symbol;

  static const List<String> _chars = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ]; // dart format off

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(symbol.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(t('Üzerine yazılacak harf/rakam (isteğe bağlı)')),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ActionChip(
              key: const ValueKey('overlay_none'),
              avatar: AprsSymbolIcon(table: symbol.table, code: symbol.code, size: 24),
              label: Text(t('Yok')),
              onPressed: () => Navigator.of(context).pop(symbol.table),
            ),
            for (final c in _chars)
              ActionChip(
                key: ValueKey('overlay_$c'),
                avatar: AprsSymbolIcon(table: c, code: symbol.code, size: 24),
                label: Text(c),
                onPressed: () => Navigator.of(context).pop(c),
              ),
          ]),
        ]),
      ),
    );
  }
}
