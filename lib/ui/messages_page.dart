import 'package:flutter/material.dart';

import '../core/aprs.dart';
import '../state/app_controller.dart';
import '../state/models.dart';
import 'confirm_transmit.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _newMessage(BuildContext context) async {
    final field = TextEditingController();
    final peer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni mesaj'),
        content: TextField(
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Alıcı çağrı işareti', hintText: 'TA4RX-7'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('Aç')),
        ],
      ),
    );
    field.dispose();
    if (peer == null || peer.isEmpty || !context.mounted) return;
    if (!isUsableCallsign(peer)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geçersiz çağrı işareti.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      // Same normalisation the controller uses as conversation key.
      builder: (_) => ChatPage(controller: controller, peer: normalizeCallsign(peer)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entries = controller.conversations.entries.toList()
          ..sort((a, b) => b.value.last.time.compareTo(a.value.last.time));
        return Scaffold(
          appBar: AppBar(title: const Text('Mesajlar')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _newMessage(context),
            icon: const Icon(Icons.edit),
            label: const Text('Yeni mesaj'),
          ),
          body: entries.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Henüz mesaj yok.')))
              : ListView(
                  children: [
                    for (final e in entries)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(e.key),
                        subtitle: Text(e.value.last.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => ChatPage(controller: controller, peer: e.key),
                        )),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller, required this.peer});

  final AppController controller;
  final String peer;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final packet = widget.controller.buildMessagePacket(to: widget.peer, text: text);
      final sent = await confirmAndTransmit(context, widget.controller, packet);
      if (sent && mounted) _input.clear();
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _stateLabel(DeliveryState s) => switch (s) {
        DeliveryState.sent => 'gönderildi',
        DeliveryState.heardBack => 'digipeater tekrarladı',
        DeliveryState.acked => 'onaylandı',
        DeliveryState.rejected => 'reddedildi',
        DeliveryState.failed => 'başarısız',
        DeliveryState.none => '',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.peer)),
      body: Column(children: [
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final messages = widget.controller.conversations[widget.peer] ?? const <ChatMessage>[];
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final m = messages[i];
                  final mine = m.direction == MessageDirection.outgoing;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(10),
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                      decoration: BoxDecoration(
                        color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.text),
                        if (mine)
                          Text(_stateLabel(m.state), style: Theme.of(context).textTheme.labelSmall),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: kMaxMessageLength,
                  decoration: const InputDecoration(hintText: 'Mesaj (yalnızca ASCII, Türkçe harf yok)'),
                ),
              ),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
