import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

class MessagePage extends StatefulWidget {
  final String relationshipId;

  const MessagePage({super.key, required this.relationshipId});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController(); // ⭐ 新增
  bool _sending = false;
  int _lastMessageCount = 0;
  bool _initialScrolled = false;

  Future<void> _sendMessage() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() => _sending = true);
    _ctrl.clear();

    final db = FirebaseFirestore.instance;
    final relRef = db.collection('relationships').doc(widget.relationshipId);

    try {
      // ===== ① 存聊天紀錄 =====
      await relRef.collection('messages').add({
        'fromUid': uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ===== ② 跟 NotificationService 一樣：從 users/{uid} 讀 partnerUid =====
      final mySnap = await db.collection('users').doc(uid).get();
      final myData = mySnap.data();
      final partnerUid = myData?['partnerUid'] as String?;
      if (partnerUid == null) return;

      // ===== ③ 讀暱稱（這段你原本就 OK）=====
      final partnerSnap = await db.collection('users').doc(partnerUid).get();
      final partnerData = partnerSnap.data();

      final myNickname = (partnerData?['relationship']?['nickname'] as String?)
          ?.trim();

      final mySnap2 = await db.collection('users').doc(uid).get();
      final myDisplayName = (mySnap2.data()?['displayName'] as String?)?.trim();

      final title = (myNickname != null && myNickname.isNotEmpty)
          ? myNickname
          : (myDisplayName != null && myDisplayName.isNotEmpty)
          ? myDisplayName
          : '兄弟';

      // ===== ④ 丟通知 =====
      await NotificationService.instance.sendToPartner(
        relationshipId: widget.relationshipId,
        text: text,
        title: title,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // void _scrollToBottom() {
  //   if (!_scrollCtrl.hasClients) return;

  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     if (!_scrollCtrl.hasClients) return;

  //     final max = _scrollCtrl.position.maxScrollExtent;

  //     // ⭐ 先瞬移，確保位置正確
  //     _scrollCtrl.jumpTo(max);

  //     // ⭐ 下一幀再動畫，避免差一點
  //     WidgetsBinding.instance.addPostFrameCallback((_) {
  //       if (!_scrollCtrl.hasClients) return;
  //       _scrollCtrl.animateTo(
  //         _scrollCtrl.position.maxScrollExtent,
  //         duration: const Duration(milliseconds: 120),
  //         curve: Curves.easeOutCubic,
  //       );
  //     });
  //   });
  // }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('訊息')),
      body: Column(
        children: [
          // ===== 上方訊息列表 =====
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('relationships')
                  .doc(widget.relationshipId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? [];

                // ⭐ 第一次進來（只做一次）
                if (!_initialScrolled && docs.isNotEmpty) {
                  _initialScrolled = true;
                  _lastMessageCount = docs.length;
                  // _scrollToBottom();
                }

                if (docs.length > _lastMessageCount) {
                  _lastMessageCount = docs.length;
                  // _scrollToBottom();
                }

                // if (docs.isNotEmpty) {
                //   _scrollToBottom();
                // }

                if (docs.isEmpty) {
                  return const Center(child: Text('還沒有訊息 👀'));
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final text = data['text'] as String? ?? '';
                    final fromUid = data['fromUid'] as String?;
                    final ts = data['createdAt'] as Timestamp?;
                    final sent = data['sent'] == true;

                    final isMe = fromUid == myUid;
                    final time = ts != null
                        ? TimeOfDay.fromDateTime(ts.toDate()).format(context)
                        : '';

                    return _MessageBubble(
                      text: text,
                      isMe: isMe,
                      time: time,
                      sent: sent,
                    );
                  },
                );
              },
            ),
          ),

          // ===== 下方輸入列 =====
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: '輸入訊息…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.send_rounded,
                color: _sending
                    ? Colors.grey
                    : Theme.of(context).colorScheme.primary,
              ),
              onPressed: _sending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String time;
  final bool sent;

  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.time,
    required this.sent,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isMe
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(text),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: Theme.of(context).textTheme.labelSmall),
                if (isMe && sent) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
