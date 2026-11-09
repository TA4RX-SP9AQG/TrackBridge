import 'package:flutter/material.dart';

import '../core/aprs.dart';
import '../core/time_format.dart';
import '../state/app_controller.dart';
import '../state/models.dart';
import 'app_theme.dart';
import 'confirm_transmit.dart';
import 'wavelog_dialog.dart';
import 'widgets/ui_kit.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _newMessage(BuildContext context) async {
    final field = TextEditingController();
    final peer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.edit_outlined),
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
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Yeni mesaj'),
          ),
          body: entries.isEmpty
              ? const EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Henüz mesaj yok',
                  message: 'Gelen ve gönderdiğiniz APRS mesajları burada görünür. '
                      '"Yeni mesaj" ile bir çağrı işaretine yazabilirsiniz.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Gaps.l, Gaps.s, Gaps.l, 96),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gaps.s),
                  itemBuilder: (context, i) => _ConversationTile(
                    peer: entries[i].key,
                    last: entries[i].value.last,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ChatPage(controller: controller, peer: entries[i].key),
                    )),
                  ),
                ),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.peer, required this.last, required this.onTap});

  final String peer;
  final ChatMessage last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = last.direction == MessageDirection.outgoing;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: Gaps.l, vertical: Gaps.m),
      child: Row(children: [
        InitialsAvatar(peer, size: 48),
        const SizedBox(width: Gaps.l),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(peer, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
              Text(
                formatClock(last.time),
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
            const SizedBox(height: 2),
            Text(
              '${mine ? 'Siz: ' : ''}${last.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
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
  void initState() {
    super.initState();
    // Looking at this chat: its messages are read and need no notification.
    widget.controller.setActiveChat(widget.peer);
  }

  @override
  void dispose() {
    widget.controller.setActiveChat(null);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          if (widget.controller.settings.wavelogConfig.isComplete)
            IconButton(
              tooltip: "Wavelog'a kaydet",
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () => logToWavelogWithConfirmation(context, widget.controller, widget.peer),
            ),
        ],
        title: Row(children: [
          InitialsAvatar(widget.peer, size: 36),
          const SizedBox(width: Gaps.m),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.peer, style: theme.textTheme.titleMedium),
            Text('APRS mesajı', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final messages = widget.controller.conversations[widget.peer] ?? const <ChatMessage>[];
              if (messages.isEmpty) {
                return const EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'Henüz mesaj yok',
                  message: 'İlk mesajı aşağıdan yazın. Göndermeden önce paketi görüp onaylarsınız.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(Gaps.l),
                itemCount: messages.length,
                itemBuilder: (context, i) => _Bubble(message: messages[i]),
              );
            },
          ),
        ),
        _Composer(controller: _input, onSend: _send),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  (IconData, String)? _status() => switch (message.state) {
        DeliveryState.sent => (Icons.check_rounded, 'gönderildi'),
        DeliveryState.heardBack => (Icons.repeat_rounded, 'digipeater tekrarladı'),
        DeliveryState.acked => (Icons.done_all_rounded, 'onaylandı'),
        DeliveryState.rejected => (Icons.block_rounded, 'reddedildi'),
        DeliveryState.failed => (Icons.error_outline_rounded, 'başarısız'),
        DeliveryState.none => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mine = message.direction == MessageDirection.outgoing;
    final background = mine ? scheme.primary : scheme.surfaceContainerHigh;
    final foreground = mine ? scheme.onPrimary : scheme.onSurface;
    final meta = foreground.withValues(alpha: 0.82);
    final status = mine ? _status() : null;
    const big = Radius.circular(Radii.l);
    const small = Radius.circular(4);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: Gaps.xs),
        padding: const EdgeInsets.fromLTRB(Gaps.l, Gaps.m, Gaps.l, Gaps.s),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.only(
            topLeft: big,
            topRight: big,
            bottomLeft: mine ? big : small,
            bottomRight: mine ? small : big,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message.text, style: theme.textTheme.bodyLarge?.copyWith(color: foreground)),
          const SizedBox(height: Gaps.xs),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(formatClock(message.time), style: theme.textTheme.labelSmall?.copyWith(color: meta)),
            if (status != null) ...[
              const SizedBox(width: Gaps.s),
              ExcludeSemantics(child: Icon(status.$1, size: 14, color: meta)),
              const SizedBox(width: Gaps.xs),
              Text(status.$2, style: theme.textTheme.labelSmall?.copyWith(color: meta)),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.l, Gaps.s, Gaps.s, Gaps.s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => TextField(
                  controller: controller,
                  maxLength: kMaxMessageLength,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Mesaj yazın (yalnızca ASCII)',
                    counterText: '',
                    suffixText: '${value.text.length}/$kMaxMessageLength',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.xl)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.xl),
                      borderSide: BorderSide(color: scheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.xl),
                      borderSide: BorderSide(color: scheme.primary, width: 2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Gaps.s),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: IconButton.filled(
                tooltip: 'Gönder (telsizle yayınlanır)',
                onPressed: onSend,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.tertiary,
                  foregroundColor: scheme.onTertiary,
                  minimumSize: const Size(52, 52),
                ),
                icon: const Icon(Icons.send_rounded),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
