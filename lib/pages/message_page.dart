import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../app_runtime_state.dart';
import 'dart:async';
import 'dart:math' as Math;

final GlobalKey<_MessagePageState> messagePageStateKey =
    GlobalKey<_MessagePageState>();

class MessagePage extends StatefulWidget {
  const MessagePage({Key? key, required this.relationshipId}) : super(key: key);
  final String relationshipId;

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

  static const List<Map<String, String>> animalOptions = [
    {'id': 'cat', 'label': '貓咪', 'emoji': '🐱'},
    {'id': 'dog', 'label': '狗狗', 'emoji': '🐶'},
    {'id': 'rabbit', 'label': '兔子', 'emoji': '🐰'},
    {'id': 'bear', 'label': '小熊', 'emoji': '🐻'},
    {'id': 'fox', 'label': '狐狸', 'emoji': '🦊'},
    {'id': 'tiger', 'label': '老虎', 'emoji': '🐯'},
    {'id': 'panda', 'label': '熊貓', 'emoji': '🐼'},
    {'id': 'hamster', 'label': '倉鼠', 'emoji': '🐹'},
    {'id': 'duck', 'label': '小鴨', 'emoji': '🦆'},
    {'id': 'dinosaur', 'label': '恐龍', 'emoji': '🦖'},
    {'id': 'mermaid', 'label': '美人魚', 'emoji': '🧜'},
    {'id': 'santa', 'label': '聖誕老人', 'emoji': '🧑‍🎄'},
  ];

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

  Future<void> _updateReadMessageCountWithTotal(int totalCount) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'read_message_count': totalCount,
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

  Future<void> sendPetRequest() async {
    if (_sending) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() => _sending = true);

    final db = FirebaseFirestore.instance;
    final relRef = db.collection('relationships').doc(widget.relationshipId);

    try {
      // 1. 存入 Firestore，增加 type: 'pet_request'
      await relRef.collection('messages').add({
        'fromUid': uid,
        'text': '討摸摸 ❤️', // 預留文字給不支援特殊 UI 的地方看
        'type': 'pet_request',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. 獲取暱稱邏輯（複用發送訊息的邏輯）
      final mySnap = await db.collection('users').doc(uid).get();
      final partnerUid = mySnap.data()?['partnerUid'];
      if (partnerUid == null) return;

      final partnerSnap = await db.collection('users').doc(partnerUid).get();
      final myNickname = partnerSnap.data()?['relationship']?['nickname'];
      final title = (myNickname != null && myNickname.isNotEmpty)
          ? myNickname
          : '對方';

      // 3. 發送通知
      // await NotificationService.instance.sendToPartner(
      //   relationshipId: widget.relationshipId,
      //   text: '向你發出了一個討摸摸請求！',
      //   title: title,
      // );

      // 滾動到最新
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
                if (AppRuntimeState.currentChatRelationshipId ==
                    widget.relationshipId) {
                  _updateReadMessageCountWithTotal(docs.length);
                }
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

                    final type = data['type'] as String?;
                    final petStatus = data['status'] as String?;

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
                        type: type,
                        petStatus: petStatus,
                        replyPreview: data['replyTo'],
                        eventTitle: data['eventTitle'],
                        remainText: data['remainText'],
                        targetAt: data['targetAt'],
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

  Future<void> _sendCountdownMessage() async {
    if (_sending) return;

    final db = FirebaseFirestore.instance;
    final relRef = db.collection('relationships').doc(widget.relationshipId);

    final relSnap = await relRef.get();
    final countdown = relSnap.data()?['countdown'];

    if (countdown == null || countdown['enabled'] != true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('尚未啟用倒數')));
      return;
    }

    final targetTimestamp = countdown['targetAt'] as Timestamp?;
    final eventTitle = countdown['eventTitle'] ?? '重要日子';

    if (targetTimestamp == null) return;

    final target = targetTimestamp.toDate();
    final now = DateTime.now();
    final diff = target.difference(now);

    String remainText;

    if (diff.isNegative) {
      remainText = '已經到了 🎉';
    } else {
      final totalSeconds = diff.inSeconds;

      final hours = totalSeconds ~/ 3600;
      final minutes = (totalSeconds % 3600) ~/ 60;
      final seconds = totalSeconds % 60;

      remainText = '還有 $hours 小時 $minutes 分 $seconds 秒';
    }

    await relRef.collection('messages').add({
      'type': 'countdown',
      'text': '距離 $eventTitle 的倒數計時',
      'eventTitle': eventTitle,
      'targetAt': targetTimestamp,
      'createdAt': FieldValue.serverTimestamp(),
      'fromUid': FirebaseAuth.instance.currentUser!.uid,
    });
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

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
        ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⭐⭐⭐ 展開選單區
            Row(
              children: [
                // ⭐ 左下角展開按鈕
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onSelected: (value) {
                    if (value == 'countdown') {
                      _sendCountdownMessage();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'countdown',
                      child: Row(
                        children: [
                          Icon(Icons.timer, size: 20),
                          SizedBox(width: 8),
                          Text('發送倒數'),
                        ],
                      ),
                    ),
                  ],
                ),

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
  final String? type;
  final Map<String, dynamic>? replyPreview;
  final String? petStatus;
  final String? eventTitle;
  final String? remainText;
  final Timestamp? targetAt;

  const _MessageBubble({
    required this.messageId,
    required this.text,
    required this.isMe,
    required this.time,
    required this.sent,
    this.type,
    this.replyPreview,
    this.petStatus,
    this.eventTitle,
    this.remainText,
    this.targetAt,
    super.key,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _offset;
  Timer? _timer;
  String _remainText = '';

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

    // ⭐⭐ 如果是 countdown 就啟動計時器
    if (widget.type == 'countdown' && widget.targetAt != null) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _updateRemainText();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemainText();
    });
  }

  void _updateRemainText() {
    final target = widget.targetAt!.toDate();
    final now = DateTime.now();
    final diff = target.difference(now);

    if (diff.isNegative) {
      setState(() {
        _remainText = '已經到了 🎉';
      });
      _timer?.cancel();
      return;
    }
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    List<String> parts = [];

    if (days > 0) {
      parts.add('$days 天');
    }
    if (hours > 0) {
      parts.add('$hours 小時');
    }
    if (minutes > 0) {
      parts.add('$minutes 分');
    }
    if (seconds > 0 || parts.isEmpty) {
      // ⭐ 如果全部都是 0，至少顯示秒
      parts.add('$seconds 秒');
    }

    setState(() {
      _remainText = '還有 ${parts.join(' ')}';
    });
  }

  Future<void> showAnimalsOverlay(BuildContext context) async {
    final overlay = Overlay.of(context);

    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final pageState = context.findAncestorStateOfType<_MessagePageState>();
    if (pageState == null) return;

    final db = FirebaseFirestore.instance;

    // ① 讀自己
    final mySnap = await db.collection('users').doc(myUid).get();
    final myAnimal = mySnap.data()?['relationship']?['animal'];

    // ② 讀對方
    final partnerUid = pageState._partnerUid;
    String? partnerAnimal;

    if (partnerUid != null) {
      final partnerSnap = await db.collection('users').doc(partnerUid).get();
      partnerAnimal = partnerSnap.data()?['relationship']?['animal'];
    }

    String getEmoji(String? id) {
      final found = _MessagePageState.animalOptions.firstWhere(
        (e) => e['id'] == id,
        orElse: () => {'emoji': '🐶'},
      );
      return found['emoji']!;
    }

    final myEmoji = getEmoji(myAnimal);
    final partnerEmoji = getEmoji(partnerAnimal);

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _TwoAnimalsOverlay(
        topEmoji: myEmoji,
        bottomEmoji: partnerEmoji,
        onFinish: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }

  void highlight() {
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Widget _buildPetDoneUI(BuildContext context) {
    return GestureDetector(
      onTap: () => showAnimalsOverlay(context),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.pink.shade50,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '你們互相摸摸了 ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.pinkAccent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPetResponseUI(BuildContext context) {
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.pink.shade200,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          '摸摸你 💞',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildPetRequestUI(BuildContext context) {
    final status = widget.petStatus;
    final isAccepted = status == 'accepted';

    if (status == 'accepted') {
      return _buildPetDoneUI(context);
    }
    if (widget.type == 'pet_response') {
      return _buildPetResponseUI(context);
    }

    final canTap = !widget.isMe && !isAccepted;

    return GestureDetector(
      onTap: canTap ? () => _onPetRequestTap(context) : null,
      child: Align(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: widget.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isAccepted
                        ? [Colors.pink.shade100, Colors.pink.shade100]
                        : [
                            Colors.pink.shade400,
                            Colors.pink.shade300,
                            Colors.orange.shade300,
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.pinkAccent.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAccepted ? Icons.favorite : Icons.favorite_border,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isAccepted
                          ? '你們互相摸摸了 '
                          : (widget.isMe ? '你發出了討摸摸' : '向你討摸摸'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.time,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onPetRequestTap(BuildContext context) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final pageState = context.findAncestorStateOfType<_MessagePageState>();
    if (pageState == null) return;

    final db = FirebaseFirestore.instance;
    final msgRef = db
        .collection('relationships')
        .doc(pageState.widget.relationshipId)
        .collection('messages')
        .doc(widget.messageId);

    // ⭐⭐⭐ 先跳出狗狗 emoji
    await showAnimalsOverlay(context);

    // ① 更新原本的 pet_request
    await msgRef.update({
      'status': 'accepted',
      'acceptedBy': myUid,
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    // ② 發通知
    await NotificationService.instance.sendToPartner(
      relationshipId: pageState.widget.relationshipId,
      title: '一切都會變好ㄉ',
      text: '你的摸摸回來了~',
    );
  }

  Widget _buildCountdownUI(BuildContext context) {
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: widget.isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade500, Colors.purple.shade300],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '距離 ${widget.eventTitle ?? ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _remainText,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ⭐⭐ 下方顯示傳送時間
            Text(widget.time, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? reply =
        widget.replyPreview is Map<String, dynamic>
        ? widget.replyPreview as Map<String, dynamic>
        : null;
    final bgColor = widget.isMe
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    if (widget.type == 'pet_request') {
      return _buildPetRequestUI(context);
    }
    if (widget.type == 'countdown') {
      return _buildCountdownUI(context);
    }

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
                    if (reply != null)
                      GestureDetector(
                        onTap: () {
                          final targetId = reply['messageId'];
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
                                        .doc(reply['fromUid'])
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
                                      reply['text'] ?? '',
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

class _BigDogEmojiOverlay extends StatefulWidget {
  final VoidCallback onFinish;
  const _BigDogEmojiOverlay({required this.onFinish});

  @override
  State<_BigDogEmojiOverlay> createState() => _BigDogEmojiOverlayState();
}

class _BigDogEmojiOverlayState extends State<_BigDogEmojiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _removed = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.1), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9), weight: 40),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));

    _ctrl.addListener(() {
      if (_ctrl.value >= 0.98 && !_removed) {
        _removed = true;
        widget.onFinish();
      }
    });

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Opacity(
              opacity: _opacity.value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: _scale.value.clamp(0.0, 3.0),
                child: const Text('🐶', style: TextStyle(fontSize: 220)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TwoAnimalsOverlay extends StatefulWidget {
  final String topEmoji;
  final String bottomEmoji;
  final VoidCallback onFinish;

  const _TwoAnimalsOverlay({
    required this.topEmoji,
    required this.bottomEmoji,
    required this.onFinish,
  });

  @override
  State<_TwoAnimalsOverlay> createState() => _TwoAnimalsOverlayState();
}

class _TwoAnimalsOverlayState extends State<_TwoAnimalsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  bool _removed = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scale = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _fade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_removed) {
        _removed = true;
        Future.delayed(const Duration(milliseconds: 300), widget.onFinish);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double emojiSize = screenWidth * 0.3;

    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ❤️ 愛心粒子層
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _HeartBurstPainter(progress: _ctrl.value),
                size: Size.infinite,
              ),
            ),

            // 🐾 動物層
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(0, emojiSize),
                        child: Text(
                          widget.topEmoji,
                          style: TextStyle(fontSize: emojiSize, height: 0.85),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, -emojiSize),
                        child: Text(
                          widget.bottomEmoji,
                          style: TextStyle(fontSize: emojiSize, height: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartBurstPainter extends CustomPainter {
  final double progress;
  final int heartCount = 10; // ❤️ 增加數量

  _HeartBurstPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // ⭐ 半徑改為依螢幕比例
    final maxRadius = size.shortestSide * 1.2;

    // ⭐ 曲線讓前段爆得快
    final curved = Curves.easeOut.transform(progress);

    for (int i = 0; i < heartCount; i++) {
      final angle = (i / heartCount) * 2 * Math.pi;

      final radius = maxRadius * curved;

      final offset = Offset(
        center.dx + radius * Math.cos(angle),
        center.dy + radius * Math.sin(angle),
      );

      final opacity = (1 - progress).clamp(0.0, 1.0);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '💗',
          style: TextStyle(
            fontSize: 44 * (1 - progress * 0.6), // ❤️ 愛心也放大
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      canvas.save();
      canvas.translate(
        offset.dx - textPainter.width / 2,
        offset.dy - textPainter.height / 2,
      );

      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HeartBurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
