import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackbridge/l10n/app_strings.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/state/settings_store.dart';
import 'package:trackbridge/ui/rebuild.dart';
import 'package:trackbridge/ui/settings_page.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

import 'helpers/fakes.dart';

Future<AppController> controllerWith(String language, {String? system}) async {
  final controller = AppController(
    link: FakeLink(),
    store: MemoryStore(AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true, language: language)),
    systemLanguage: system,
  );
  await controller.init();
  return controller;
}

void main() {
  tearDown(() => L10n.setLanguage(AppLanguage.turkish));

  test('the stored language is applied when the controller starts', () async {
    await controllerWith('en');
    expect(L10n.language, AppLanguage.english);
    await controllerWith('tr', system: 'en');
    expect(L10n.language, AppLanguage.turkish);
  });

  test('"system" follows the phone language', () async {
    await controllerWith('system', system: 'tr');
    expect(L10n.language, AppLanguage.turkish);
    await controllerWith('system', system: 'de');
    expect(L10n.language, AppLanguage.english);
  });

  test('without a phone language and with "system" the language is left alone', () async {
    L10n.setLanguage(AppLanguage.english);
    await controllerWith('system');
    expect(L10n.language, AppLanguage.english);
  });

  test('changing the setting switches the language at once', () async {
    final controller = await controllerWith('tr', system: 'tr');
    await controller.updateSettings(controller.settings.copyWith(language: 'en'));
    expect(L10n.language, AppLanguage.english);
    await controller.updateSettings(controller.settings.copyWith(language: 'system'));
    expect(L10n.language, AppLanguage.turkish);
  });

  test('the preference is stored, and an unknown stored value falls back to "system"', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsSettingsStore();
    await store.save(const AppSettings(language: 'en'));
    expect((await store.load()).language, 'en');
    SharedPreferences.setMockInitialValues({'tb.language': 'klingon'});
    expect((await store.load()).language, 'system');
    SharedPreferences.setMockInitialValues({});
    expect((await store.load()).language, 'system');
  });

  testWidgets('choosing English in Settings translates the open screen without leaving it', (tester) async {
    await tester.runAsync(SymbolSheets.load);
    final controller = await controllerWith('tr', system: 'tr');
    var shown = L10n.language;
    controller.addListener(() {
      if (shown == L10n.language) return;
      shown = L10n.language;
      rebuildEverything();
    });
    await tester.pumpWidget(MaterialApp(home: SettingsPage(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('English'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(controller.settings.language, 'en');
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Ayarlar'), findsNothing);
    expect(find.text('Phone language'), findsOneWidget);
  });
}
