import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'beacon_page.dart';
import 'connect_page.dart';
import 'messages_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  bool _noticeShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNoticeIfNeeded());
  }

  Future<void> _showNoticeIfNeeded() async {
    final controller = widget.controller;
    if (_noticeShown || controller.settings.noticeAccepted || !mounted) return;
    _noticeShown = true;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Amatör telsiz uyarısı'),
        content: const Text(
          'TrackBridge, LoRa APRS tracker\'ınız üzerinden amatör telsiz frekanslarında yayın yapar. '
          'Yayın için geçerli bir amatör telsiz lisansına sahip olmanız ve kendi çağrı işaretinizi '
          'kullanmanız gerekir. Gönderdiğiniz her paketten siz sorumlusunuz; paketler internete '
          'düşerse herkese açık görünür.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Anladım'))],
      ),
    );
    if (accepted ?? false) {
      await controller.updateSettings(controller.settings.copyWith(noticeAccepted: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pages = <Widget>[
      ConnectPage(controller: controller),
      MessagesPage(controller: controller),
      BeaconPage(controller: controller),
      SettingsPage(controller: controller),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Bağlantı'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Mesajlar'),
          NavigationDestination(icon: Icon(Icons.cell_tower), label: 'Beacon'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Ayarlar'),
        ],
      ),
    );
  }
}
