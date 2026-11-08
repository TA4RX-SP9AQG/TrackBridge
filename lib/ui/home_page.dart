import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'beacon_page.dart';
import 'connect_page.dart';
import 'map_page.dart';
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

  /// The map is built the first time its tab is opened, so no map tiles are
  /// requested for users who never look at it.
  bool _mapOpened = false;
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
        icon: const Icon(Icons.verified_user_outlined),
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
      _mapOpened ? MapPage(controller: controller) : const SizedBox.shrink(),
      MessagesPage(controller: controller),
      BeaconPage(controller: controller),
      SettingsPage(controller: controller),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          if (i == 1) _mapOpened = true;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bluetooth_rounded),
            selectedIcon: Icon(Icons.bluetooth_connected_rounded),
            label: 'Bağlantı',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Harita',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Mesajlar',
          ),
          NavigationDestination(
            icon: Icon(Icons.cell_tower_rounded),
            selectedIcon: Icon(Icons.cell_tower_rounded),
            label: 'Beacon',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Ayarlar',
          ),
        ],
      ),
    );
  }
}
