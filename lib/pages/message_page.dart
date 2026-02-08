import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../app_runtime_state.dart';

class MessagePage extends StatefulWidget {
  final String relationshipId;

  const MessagePage({super.key, required this.relationshipId});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  final Map<String, GlobalKey<_MessageBubbleState>> _bubbleKeys = {};
  bool _sending = false;
  String? _partnerUid;
  final Map<String, int> _messageIndex = {};

  String? _replyToMessageId;
  String? _replyToText;
  String? _replyToFromUid;

  @override
  void initState() {
    super.initState();
    _loadPartnerUid();
    AppRuntimeState.currentChatRelationshipId = widget.relationshipId;
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

        if (_replyToMessageId != null)
          'replyTo': {
            'messageId': _replyToMessageId,
            'text': _replyToText,
            'fromUid': _replyToFromUid,
          },
      });

      setState(() {
        _replyToMessageId = null;
        _replyToText = null;
        _replyToFromUid = null;
      });

      // ===== ② 讀取 partnerUid =====
      final mySnap = await db.collection('users').doc(uid).get();
      final myData = mySnap.data();
      final partnerUid = myData?['partnerUid'] as String?;
      if (partnerUid == null) return;

      // ===== ③ 讀取暱稱 =====
      final partnerSnap = await db.collection('users').doc(partnerUid).get();
      final partnerData = partnerSnap.data();

      final myNickname = (partnerData?['relationship']?['nickname'] as String?)
          ?.trim();
      final myDisplayName = (mySnap.data()?['displayName'] as String?)?.trim();

      final title = (myNickname != null && myNickname.isNotEmpty)
          ? myNickname
          : (myDisplayName != null && myDisplayName.isNotEmpty)
          ? myDisplayName
          : '對方';

      await Future.delayed(const Duration(milliseconds: 1));

      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0, // ⭐ reverse:true 時，0 = 最新訊息
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
      // ===== ④ 發送通知 =====
      await NotificationService.instance.sendToPartner(
        relationshipId: widget.relationshipId,
        text: text,
        title: title,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    AppRuntimeState.currentChatRelationshipId = null;
    super.dispose();
  }

  void _jumpToMessage(String messageId) async {
    final index = _messageIndex[messageId];
    if (index == null) return;

    // ① 先滑到大概位置
    await _scrollCtrl.animateTo(
      index * 72.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );

    // ② 等 widget build
    await Future.delayed(const Duration(milliseconds: 60));

    final key = _bubbleKeys[messageId];
    if (key == null || key.currentContext == null) return;

    // ③ 精準滑到定點
    await Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.3,
    );

    // ④ 關鍵：等滑動完全停止「一拍」
    await Future.delayed(const Duration(milliseconds: 200));

    // ⑤ 再擺動（一定看得到）
    key.currentState?.highlight();
  }

  void _showBatteryInfo(
    BuildContext context,
    int level,
    Timestamp? updatedAt,
    bool isCharging,
  ) {
    final time = updatedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(updatedAt.millisecondsSinceEpoch)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final width = MediaQuery.of(context).size.width;

        return Container(
          width: width,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('訊息'),
            if (_partnerUid != null)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(_partnerUid)
                    .snapshots(),
                builder: (context, snap) {
                  final updatedAt =
                      snap.data?.data()?['battery']?['updatedAt'] as Timestamp?;
                  final status = _formatOnlineStatus(updatedAt);
                  final isOnline = status == '上線中';

                  return Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: isOnline ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
        actions: [
          if (_partnerUid != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_partnerUid)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Icon(Icons.battery_unknown);

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
                  onPressed: () =>
                      _showBatteryInfo(context, level, updatedAt, isCharging),
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
                final aliveIds = docs.map((e) => e.id).toSet();
                _bubbleKeys.removeWhere((key, _) => !aliveIds.contains(key));
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
                    final doc = docs[i];
                    final data = doc.data();
                    final messageId = doc.id;
                    _messageIndex[messageId] = i;

                    final bubbleKey = _bubbleKeys.putIfAbsent(
                      messageId,
                      () => GlobalKey<_MessageBubbleState>(),
                    );

                    final text = data['text'] ?? '';
                    final fromUid = data['fromUid'];
                    final ts = data['createdAt'] as Timestamp?;
                    final sent = data['sent'] == true;
                    final isMe = fromUid == myUid;
                    final time = ts != null
                        ? TimeOfDay.fromDateTime(ts.toDate()).format(context)
                        : '';

                    return SwipeToReplyWrapper(
                      onReply: () {
                        setState(() {
                          _replyToMessageId = messageId;
                          _replyToText = text;
                          _replyToFromUid = fromUid;
                        });
                        FocusScope.of(context).requestFocus(_inputFocus);
                      },
                      child: _MessageBubble(
                        key: bubbleKey,
                        messageId: messageId,
                        text: text,
                        isMe: isMe,
                        time: time,
                        sent: sent,
                        replyPreview: data['replyTo'],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_replyToText != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                border: Border(
                  left: BorderSide(
                    width: 4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '回覆：$_replyToText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _replyToMessageId = null;
                        _replyToText = null;
                        _replyToFromUid = null;
                      });
                    },
                  ),
                ],
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
      builder: (context) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: MediaQuery.of(context).size.width,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.battery_unknown, size: 40, color: Colors.grey),
                const SizedBox(height: 12),
                Text('電池狀態未知', style: Theme.of(context).textTheme.titleMedium),
                if (level != null) Text('上次回報電量：$level%'),
                if (time != null)
                  Text(
                    '上次更新時間：${TimeOfDay.fromDateTime(time).format(context)}',
                  ),
                const SizedBox(height: 12),
                const Text(
                  '資料已超過 1 小時未更新\n可能是對方裝置未回報或暫時離線',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatOnlineStatus(Timestamp? updatedAt) {
    if (updatedAt == null) return '離線';
    final last = updatedAt.toDate();
    final now = DateTime.now();
    final diff = now.difference(last);
    if (diff.inSeconds < 30) return '上線中';
    if (diff.inMinutes < 1 && diff.inSeconds >= 40) return '30 秒前上線';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前上線';
    if (diff.inHours < 24) return '${diff.inHours} 小時前上線';
    return '${diff.inDays} 天前上線';
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
                focusNode: _inputFocus,
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

class _MessageBubble extends StatefulWidget {
  final String messageId;
  final String text;
  final bool isMe;
  final String time;
  final bool sent;
  final Map<String, dynamic>? replyPreview;

  const _MessageBubble({
    required this.messageId,
    required this.text,
    required this.isMe,
    required this.time,
    required this.sent,
    this.replyPreview,
    super.key,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _offset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  void highlight() {
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isMe
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_offset.value, 0),
          child: child,
        );
      },
      child: Align(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: widget.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.replyPreview != null)
                      GestureDetector(
                        onTap: () {
                          final targetId = widget.replyPreview!['messageId'];
                          final pageState = context
                              .findAncestorStateOfType<_MessagePageState>();
                          pageState?._jumpToMessage(targetId);
                        },
                        child: IntrinsicWidth(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.reply,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  FutureBuilder<
                                    DocumentSnapshot<Map<String, dynamic>>
                                  >(
                                    future: FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(widget.replyPreview!['fromUid'])
                                        .get(),
                                    builder: (context, snap) {
                                      final photoUrl =
                                          snap.data?.data()?['photoURL']
                                              as String?;
                                      return CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.grey.shade300,
                                        backgroundImage: photoUrl != null
                                            ? NetworkImage(photoUrl)
                                            : null,
                                        child: photoUrl == null
                                            ? const Icon(Icons.person, size: 12)
                                            : null,
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      widget.replyPreview!['text'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    Text(widget.text),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.time,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (widget.isMe && widget.sent) ...[
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
    IconData icon = isCharging
        ? Icons.battery_charging_full
        : Icons.battery_full;
    final color = level <= 20
        ? Colors.red
        : Theme.of(context).colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        Text('$level%', style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}

class SwipeToReplyWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const SwipeToReplyWrapper({
    super.key,
    required this.child,
    required this.onReply,
  });

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _dx = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) =>
          setState(() => _dx = (_dx + d.delta.dx).clamp(-60, 60)),
      onHorizontalDragEnd: (_) {
        if (_dx.abs() >= 18) widget.onReply();
        _ctrl.forward(from: 0);
        final anim = Tween<double>(
          begin: _dx,
          end: 0,
        ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
        anim.addListener(() => setState(() => _dx = anim.value));
      },
      child: Transform.translate(offset: Offset(_dx, 0), child: widget.child),
    );
  }
}
