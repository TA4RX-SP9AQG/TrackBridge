import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/ui/app_theme.dart';
import 'package:trackbridge/ui/messages_page.dart';

import 'helpers/fakes.dart';
import 'helpers/message_fakes.dart';

void main() {
  testWidgets('opening a chat marks it read and a message arriving while it is open is not notified', (tester) async {
    final link = FakeLink();
    final notifier = FakeMessageNotifier();
    final controller = AppController(
      link: link,
      store: MemoryStore(const AppSettings(callsign: 'N0DEMO-9', noticeAccepted: true, autoAck: false)),
      notifier: notifier,
    );
    await controller.init();
    link.setConnected(true);
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Merhaba{1'));
    await tester.pump();
    expect(controller.unreadCount('N1TEST-7'), 1);

    controller.setAppForeground(true);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: ChatPage(controller: controller, peer: 'N1TEST-7')));
    await tester.pump();
    expect(controller.unreadCount('N1TEST-7'), 0);

    final before = notifier.shown.length;
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Ikinci{2'));
    await tester.pump();
    expect(notifier.shown.length, before);
    expect(controller.unreadCount('N1TEST-7'), 0);

    // leaving the chat: new messages notify again
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Ucuncu{3'));
    await tester.pump();
    expect(notifier.shown.length, before + 1);
    controller.dispose();
  });
}
