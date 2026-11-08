import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/ui/symbol_picker.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

class _Host extends StatefulWidget {
  const _Host({required this.initialTable, required this.initialCode});

  final String initialTable;
  final String initialCode;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  SymbolChoice? result;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(children: [
              TextButton(
                onPressed: () async {
                  final r = await Navigator.of(context).push<SymbolChoice>(MaterialPageRoute(
                    builder: (_) => SymbolPickerPage(initialTable: widget.initialTable, initialCode: widget.initialCode),
                  ));
                  setState(() => result = r);
                },
                child: const Text('open'),
              ),
              Text(result == null ? 'none' : 'picked:${result!.table}${result!.code}'),
            ]),
          ),
        ),
      );
}

Future<void> openPicker(WidgetTester tester, {String table = '/', String code = '-'}) async {
  await tester.runAsync(SymbolSheets.load);
  await tester.pumpWidget(_Host(initialTable: table, initialCode: code));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picking a primary symbol returns "/" and the code', (tester) async {
    await openPicker(tester);
    await tester.enterText(find.byType(TextField), 'bicycle');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('symbol_/b')));
    await tester.pumpAndSettle();
    expect(find.text('picked:/b'), findsOneWidget);
  });

  testWidgets('search with no match shows an empty message', (tester) async {
    await openPicker(tester);
    await tester.enterText(find.byType(TextField), 'zzzz-no-such');
    await tester.pumpAndSettle();
    expect(find.text('Eşleşen sembol yok'), findsOneWidget);
  });

  testWidgets('alternate symbol with overlay support asks for an overlay character', (tester) async {
    await openPicker(tester);
    await tester.tap(find.text('Alternatif'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'digipeater');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(r'symbol_\#')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('overlay_S')));
    await tester.pumpAndSettle();
    expect(find.text(r'picked:S#'), findsOneWidget);
  });

  testWidgets('overlay sheet offers "no overlay" which keeps the backslash', (tester) async {
    await openPicker(tester);
    await tester.tap(find.text('Alternatif'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gateway');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(r'symbol_\&')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('overlay_none')));
    await tester.pumpAndSettle();
    expect(find.text(r'picked:\&'), findsOneWidget);
  });

  testWidgets('alternate symbol without overlay support returns directly', (tester) async {
    await openPicker(tester);
    await tester.tap(find.text('Alternatif'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'church');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(r'symbol_\+')));
    await tester.pumpAndSettle();
    expect(find.text(r'picked:\+'), findsOneWidget);
  });

  testWidgets('opens on the table of the current choice (overlay character means alternate)', (tester) async {
    await openPicker(tester, table: 'S', code: '#');
    expect(find.byKey(const ValueKey(r'symbol_\#')), findsOneWidget);
  });

  testWidgets('reserved symbols are not offered', (tester) async {
    await openPicker(tester);
    expect(find.byKey(const ValueKey('symbol_/"')), findsNothing);
    expect(find.byKey(const ValueKey('symbol_/-')), findsOneWidget);
  });
}
