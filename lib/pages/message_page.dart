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
  String? _partnerUid;

  @override
  void initState() {
    super.initState();
    _loadPartnerUid();
  }

  Future<void> _loadPartnerUid() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    setState(() {
      _partnerUid = snap.data()?['partnerUid'];
    });
  }

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

  void _showBatteryInfo(
    BuildContext context,
    int level,
    Timestamp? updatedAt,
    bool isCharging, // ⭐ 新增
  ) {
    final time = updatedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(updatedAt.millisecondsSinceEpoch)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, // ⭐ 很重要
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final width = MediaQuery.of(context).size.width;

        return Container(
          width: width, // ⭐ 關鍵
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCharging ? Icons.battery_charging_full : Icons.battery_full,
                size: 36,
                color: level <= 20 ? Colors.red : Colors.green,
              ),
              const SizedBox(height: 8),
              Text('對方手機電量', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '$level%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (time != null)
                Text(
                  '上次更新：${TimeOfDay.fromDateTime(time).format(context)}',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                const Text('尚未更新'),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('訊息'),
        actions: [
          if (_partnerUid != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_partnerUid)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Icon(Icons.battery_unknown);
                }

                final data = snap.data!.data();
                final battery = data?['battery'];
                final level = battery?['level'] as int?;
                final updatedAt = battery?['updatedAt'] as Timestamp?;
                final isCharging = battery?['isCharging'] == true;

                final now = DateTime.now();
                final lastUpdateTime = updatedAt?.toDate();
                final isStale = lastUpdateTime == null
                    ? true
                    : now.difference(lastUpdateTime) > const Duration(hours: 1);

                if (level == null || isStale) {
                  return IconButton(
                    icon: const Icon(Icons.battery_unknown),
                    onPressed: () => _showBatteryStale(
                      context,
                      level,
                      updatedAt,
                      isCharging,
                    ),
                  );
                }

                return IconButton(
                  icon: _BatteryIcon(level: level, isCharging: isCharging),
                  onPressed: () => _showBatteryInfo(
                    context,
                    level,
                    updatedAt,
                    isCharging, // ⭐ 傳進去
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('relationships')
                  .doc(widget.relationshipId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;

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
                    final text = data['text'] ?? '';
                    final fromUid = data['fromUid'];
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
          _buildInputBar(context),
        ],
      ),
    );
  }

  void _showBatteryStale(
    BuildContext context,
    int? level,
    Timestamp? updatedAt,
    bool isCharging,
  ) {
    final time = updatedAt?.toDate();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final width = MediaQuery.of(context).size.width;

        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: width, // ✅ 100% 螢幕寬
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.battery_unknown,
                    size: 40,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '電池狀態未知',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),

                  if (level != null) Text('上次回報電量：$level%'),

                  if (time != null)
                    Text(
                      '上次更新時間：${TimeOfDay.fromDateTime(time).format(context)}',
                    ),

                  const SizedBox(height: 12),
                  Text(
                    '資料已超過 1 小時未更新\n可能是對方裝置未回報或暫時離線',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

class _BatteryIcon extends StatelessWidget {
  final int level;
  final bool isCharging;

  const _BatteryIcon({required this.level, required this.isCharging});

  @override
  Widget build(BuildContext context) {
    IconData icon;

    if (isCharging) {
      // ⭐ 只有在充電中
      icon = Icons.battery_charging_full;
    } else if (level >= 90) {
      icon = Icons.battery_full;
    } else if (level >= 60) {
      icon = Icons.battery_5_bar;
    } else if (level >= 30) {
      icon = Icons.battery_3_bar;
    } else if (level >= 15) {
      icon = Icons.battery_2_bar;
    } else {
      icon = Icons.battery_alert;
    }

    final color = level <= 20
        ? Colors.red
        : Theme.of(context).colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 2),
        Text(
          '$level%',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
            height: 1,
            color: color,
          ),
        ),
      ],
    );
  }
}
