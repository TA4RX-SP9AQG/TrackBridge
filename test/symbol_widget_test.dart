import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/symbols.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sprite sheets are bundled and have the expected 16x6 tile grid', (tester) async {
    final sheets = await tester.runAsync(SymbolSheets.load);
    expect(sheets, isNotNull);
    for (final image in [sheets!.primary, sheets.alternate, sheets.overlay]) {
      expect((image.width, image.height), (2048, 768));
    }
  });

  testWidgets('renders every catalog symbol, with and without overlay, and bad codes, without errors',
      (tester) async {
    await tester.runAsync(SymbolSheets.load);
    final icons = <Widget>[
      for (final s in [...primarySymbols, ...alternateSymbols]) AprsSymbolIcon(table: s.table, code: s.code, size: 24),
      const AprsSymbolIcon(table: 'S', code: '#', size: 24), // overlay on digipeater
      const AprsSymbolIcon(table: '7', code: '&', size: 24),
      const AprsSymbolIcon(table: '/', code: ' ', size: 24), // invalid code
      const AprsSymbolIcon(table: '@', code: '-', size: 24), // invalid table
      const AprsSymbolIcon(table: '', code: '', size: 24),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Wrap(children: icons)))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(AprsSymbolIcon), findsNWidgets(icons.length));
  });

  testWidgets('icon keeps the requested size', (tester) async {
    await tester.runAsync(SymbolSheets.load);
    await tester.pumpWidget(const MaterialApp(home: Center(child: AprsSymbolIcon(table: '/', code: '-', size: 40))));
    await tester.pump();
    expect(tester.getSize(find.byType(AprsSymbolIcon)), const Size(40, 40));
  });
}
