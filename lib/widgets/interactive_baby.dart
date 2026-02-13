import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baobao/widgets/rainbow_menu.dart';
import 'package:baobao/services/baby_service.dart';
import 'package:baobao/services/notification_service.dart';
import 'package:baobao/services/economy_service.dart';
import '../pages/message_page.dart';

class InteractiveBaby extends StatefulWidget {
  const InteractiveBaby({super.key});

  @override
  State<InteractiveBaby> createState() => _InteractiveBabyState();
}

class _InteractiveBabyState extends State<InteractiveBaby>
    with TickerProviderStateMixin {
  // Animation
  late final AnimationController _jumpCtrl;
  late final Animation<double> _jump;

  late final AnimationController _spinCtrl;
  late final Animation<double> _spin;
  Map<String, dynamic>? _countdown;
  int _handledServerLove = 0;
  int _tapForFood = 0;

  int _serverLove = 0;

  String? _relationshipId;
  String? _partnerPhotoUrl;

  String? myName;

  // Love / Sync
  int _unsyncedTaps = 0;
  int _lastSelfSynced = 0;
  int _lastServerLove = 0;
  int _displayLove = 0;
  final List<_PartnerFloat> _partnerFloats = [];
  int _partnerFloatId = 0;

  int _pendingSelfDelta = 0;
  Timer? _selfFloatTimer;

  static const _selfFloatWindow = Duration(milliseconds: 400);

  int _pendingPartnerDelta = 0;
  bool _flushScheduled = false;

  // bool _serverLoveInitialized = false;
  //food
  int _serverFood = 0; // 伺服器同步後的飼料
  int _earnedFood = 0; // 本地尚未同步的飼料
  int _myFoodEarned = 0; // server 上我一共賺的

  bool _speechVisible = false;

  static const _syncInterval = Duration(seconds: 2);
  Timer? _syncTimer;

  String? _speechText;
  Timer? _speechTimer;

  // Achievement
  int _tapCount = 0;
  Timer? _tapWindow;

  // UI
  OverlayEntry? _menuEntry;
  final List<_FloatingHeart> _hearts = [];
  int _heartId = 0;
  int get _uiLove => _serverLove + _unsyncedTaps;

  final String _mood = '開心';

  bool _saidGreetingToday = false;
  DateTime? _lastGreetingDate;

  int _lastUnreadNotified = 0; // 上一次提醒的未讀數
  bool _unreadInitialized = false;
  bool _isUnreadSpeech = false;

  Timer? _messagePollTimer;

  int _currentReadCount = 0;

  @override
  void initState() {
    super.initState();

    // ===== 原本動畫（你已有，保留）=====
    _jumpCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _jump = Tween(
      begin: 0.0,
      end: -18.0,
    ).chain(CurveTween(curve: Curves.easeOutBack)).animate(_jumpCtrl);

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _spin = Tween(
      begin: 0.0,
      end: 2 * pi,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_spinCtrl);

    // ===== 原本問候（保留）=====
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeSayGreeting();
    });
  }

  void _handleUnread(int unread) {
    if (!_unreadInitialized) {
      _unreadInitialized = true;
      _lastUnreadNotified = unread;
      return;
    }

    if (unread > 0 && unread != _lastUnreadNotified) {
      _lastUnreadNotified = unread;

      if (unread == 1) {
        _say(
          '訊息來了!!!',
          duration: const Duration(seconds: 10),
          fromUnread: true,
        );
      } else if (unread < 5) {
        _say(
          '你有 $unread 則未讀訊息',
          duration: const Duration(seconds: 10),
          fromUnread: true,
        );
      } else {
        _say(
          '爆炸🤯！$unread 則未讀',
          duration: const Duration(seconds: 10),
          fromUnread: true,
        );
      }
    }

    if (unread == 0 && _speechText != null && _isUnreadSpeech) {
      setState(() {
        _speechVisible = false;
      });

      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() {
          _speechText = null;
        });
      });

      _lastUnreadNotified = 0;
    }
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;

    if (hour >= 5 && hour < 11) {
      return '早安尼好～開心一整天';
    } else if (hour >= 11 && hour < 14) {
      return '午安尼好～記得吃飯喔';
    } else if (hour >= 14 && hour < 18) {
      return '下午啦尼好~想你了';
    } else if (hour >= 18 && hour < 22) {
      return '晚ㄤ尼好～好好休息呦 ';
    } else {
      return '尼好 該睡覺ㄌ~';
    }
  }

  void _startMessagePolling(String relationshipId, String uid) {
    _messagePollTimer?.cancel();

    _messagePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final snap = await FirebaseFirestore.instance
          .collection('relationships')
          .doc(relationshipId)
          .collection('messages')
          .count()
          .get();

      final totalMessages = snap.count ?? 0;

      final readCount = _currentReadCount ?? 0; // ⭐ 加這行

      final unread = totalMessages - readCount;

      _handleUnread(unread.clamp(0, 999999)); // ⭐ 保證 int 且不負數
    });
  }

  void _queueSelfFloat(int delta) {
    _pendingSelfDelta += delta;

    // 每次點都重設 timer
    _selfFloatTimer?.cancel();

    _selfFloatTimer = Timer(_selfFloatWindow, () {
      if (!mounted) return;

      final merged = _pendingSelfDelta;
      _pendingSelfDelta = 0;

      if (merged <= 0) return;

      final id = _partnerFloatId++;
      final dx = Random().nextDouble() * 60 - 30;
      final myPhotoUrl = FirebaseAuth.instance.currentUser?.photoURL;

      setState(() {
        _partnerFloats.add(
          _PartnerFloat(id: id, delta: merged, dx: dx, photoUrl: myPhotoUrl),
        );
      });
    });
  }

  void _maybeSayGreeting() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_lastGreetingDate == today && _saidGreetingToday) return;

    _lastGreetingDate = today;
    _saidGreetingToday = true;

    _say(_timeGreeting(), duration: const Duration(seconds: 6));
  }

  void _removePartnerFloat(int id) {
    if (!mounted) return;
    setState(() {
      _partnerFloats.removeWhere((e) => e.id == id);
    });
  }

  void _say(
    String text, {
    Duration duration = const Duration(seconds: 10),
    bool fromUnread = false,
  }) {
    _speechTimer?.cancel();

    setState(() {
      _speechText = text;
      _speechVisible = true;
      _isUnreadSpeech = fromUnread; // ⭐ 記錄來源
    });

    _speechTimer = Timer(duration, () async {
      if (!mounted) return;

      setState(() {
        _speechVisible = false;
      });

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;
      setState(() {
        _speechText = null;
      });
    });
  }

  Future<void> _resolveMyName({
    required String myUid,
    required String partnerUid,
    required Map<String, dynamic>? myUserData,
  }) async {
    // fallback：自己的 displayName
    final myDisplayName = (myUserData?['displayName'] as String?)?.trim();

    try {
      final partnerSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(partnerUid)
          .get();

      final nicknameFromPartner =
          (partnerSnap.data()?['relationship']?['nickname'] as String?)?.trim();

      if (!mounted) return;

      setState(() {
        myName = (nicknameFromPartner != null && nicknameFromPartner.isNotEmpty)
            ? nicknameFromPartner
            : (myDisplayName != null && myDisplayName.isNotEmpty)
            ? myDisplayName
            : '對方';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        myName = (myDisplayName != null && myDisplayName.isNotEmpty)
            ? myDisplayName
            : '對方';
      });
    }
  }

  void _onGetFood() {
    HapticFeedback.heavyImpact();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🍖 獲得 1 顆飼料！'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _tapWindow?.cancel();
    _syncTimer?.cancel();

    _jumpCtrl.dispose();
    _spinCtrl.dispose();
    _messagePollTimer?.cancel();
    _hideMenu();
    super.dispose();
  }

  // ===== Actions =====

  void _onTap() {
    if (_jumpCtrl.isAnimating) return;

    _jumpCtrl.forward(from: 0);
    HapticFeedback.mediumImpact();

    _unsyncedTaps++;
    _spawnHeart();
    _queueSelfFloat(1);

    _tapForFood++;

    if (_tapForFood % 50 == 0) {
      _say('嘿嘿～', duration: const Duration(seconds: 5));
      _earnedFood++;
      _onGetFood();
    }

    _handleAchievement();
    _scheduleSync();
  }

  void _handleAchievement() {
    _tapWindow ??= Timer(const Duration(seconds: 10), () {
      _tapCount = 0;
      _tapWindow = null;
    });

    _tapCount++;

    if (_tapCount >= 15) {
      _tapCount = 0;
      _tapWindow?.cancel();
      _tapWindow = null;

      if (Random().nextDouble() < 0.5) {
        _triggerSpin();
      }
    }
  }

  void _triggerSpin() {
    if (_spinCtrl.isAnimating) return;
    HapticFeedback.heavyImpact();
    _spinCtrl.forward(from: 0);
  }

  // ===== Sync =====

  void _scheduleSync() {
    if (_relationshipId == null) return;

    // ⭐ 關鍵：每次點都取消舊 timer
    _syncTimer?.cancel();

    _syncTimer = Timer(_syncInterval, () async {
      final toSyncLove = _unsyncedTaps;
      final toSyncFood = _earnedFood;

      if (toSyncLove <= 0 && toSyncFood <= 0) return;

      _lastSelfSynced = toSyncLove;

      await BabyService.syncLoveAndFood(
        relationshipId: _relationshipId!,
        pendingLove: toSyncLove,
        earnedFood: toSyncFood,
      );

      if (!mounted) return;
      setState(() {
        _unsyncedTaps -= toSyncLove;
        _earnedFood -= toSyncFood;
        _lastSelfSynced = toSyncLove;
      });
    });
  }

  void _spawnPartnerHearts(int count) {
    if (count <= 0) return;

    int i = 0;
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _spawnHeart(fromPartner: true);
      i++;

      if (i >= count) {
        timer.cancel();
      }
    });
  }

  void _spawnPartnerFloat(int delta) {
    final id = _partnerFloatId++;
    final dx = Random().nextDouble() * 80 - 40;

    setState(() {
      _partnerFloats.add(
        _PartnerFloat(id: id, delta: delta, dx: dx, photoUrl: _partnerPhotoUrl),
      );
    });
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final delta = _pendingPartnerDelta;
      _pendingPartnerDelta = 0;
      _flushScheduled = false;

      if (delta <= 0) return;

      // ❤️ 愛心動畫最多 99 顆
      final heartCount = delta > 80 ? 50 : delta;

      // ✅ 現在才安全 setState
      _spawnPartnerHearts(heartCount);

      // 🧑‍🚀 float 顯示「真實數值」
      _spawnPartnerFloat(delta);
    });
  }

  void _handleServerLove(int serverLove) {
    // 第一次 snapshot：只設 baseline
    if (_lastServerLove == 0 && serverLove > 0) {
      _lastServerLove = serverLove;
      return;
    }

    final serverDelta = serverLove - _lastServerLove;
    if (serverDelta <= 0) {
      _lastServerLove = serverLove;
      return;
    }

    final externalDelta = max(0, serverDelta - _lastSelfSynced);

    if (externalDelta > 0 && externalDelta < 100) {
      _pendingPartnerDelta += externalDelta;
      _scheduleFlush(); // ⭐ 不直接動 UI
    }

    _lastSelfSynced = 0;
    _lastServerLove = serverLove;
  }

  // ===== Hearts =====

  void _spawnHeart({bool fromPartner = false}) {
    final id = _heartId++;
    final dx = Random().nextDouble() * 100 - 40;

    setState(() {
      _hearts.add(
        _FloatingHeart(
          id: id,
          dx: dx,
          fromPartner: fromPartner, // ⭐
        ),
      );
    });
  }

  void _removeHeart(int id) {
    if (!mounted) return;
    setState(() {
      _hearts.removeWhere((h) => h.id == id);
    });
  }

  Future<bool> _confirmPetCost(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('討摸摸需要飼料'),
            content: const Text('討摸摸會消費 2 顆飼料 🍖🍖\n要繼續嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('確認'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _consumeFoodForPet(String relationshipId) async {
    final ref = FirebaseFirestore.instance
        .collection('relationships')
        .doc(relationshipId);

    try {
      return await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final food = (snap.data()?['food'] as int?) ?? 0;

        if (food < 2) {
          return false;
        }

        tx.update(ref, {'food': FieldValue.increment(-2)});

        return true;
      });
    } catch (e) {
      return false;
    }
  }

  // ===== Menu =====

  void _showMenu(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));

    _menuEntry?.remove();
    _menuEntry = OverlayEntry(
      builder: (_) => RainbowArcMenuOverlay(
        anchor: center,
        onClose: _hideMenu,
        items: [
          ArcMenuItem(
            icon: Icons.restaurant,
            label: '餵食',
            textColor: Colors.orangeAccent,
            onTap: _hideMenu,
          ),
          ArcMenuItem(
            icon: Icons.favorite,
            label: '討摸摸',
            textColor: Colors.pinkAccent,
            onTap: () async {
              _hideMenu();

              final rid = _relationshipId;
              final uid = FirebaseAuth.instance.currentUser!.uid;
              if (rid == null) return;

              // ① 確認是否要消費
              final ok = await _confirmPetCost(context);
              if (!ok) return;

              // ② 嘗試扣飼料
              final success = await _consumeFoodForPet(rid);
              if (!success) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('🍖 飼料不足，無法討摸摸')));
                return;
              }
              _say('我要摸摸!!!! ', duration: const Duration(seconds: 9));

              // ③ 扣成功 → 發送 pet_request
              await FirebaseFirestore.instance
                  .collection('relationships')
                  .doc(rid)
                  .collection('messages')
                  .add({
                    'fromUid': uid,
                    'type': 'pet_request',
                    'text': '討摸摸 ❤️',
                    'createdAt': FieldValue.serverTimestamp(),
                  });

              // ④ 通知對方
              await NotificationService.instance.sendToPartner(
                relationshipId: rid,
                title: '十萬火急',
                text: '你兄弟$myName 對你發出 Pet Pet 請求 🐾',
              );

              // ⑤ 成功回饋
              if (mounted) {
                HapticFeedback.heavyImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('💖 已消費 2 顆飼料，討摸摸送出！')),
                );
              }
            },
          ),
        ],
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_menuEntry!);
    HapticFeedback.mediumImpact();
  }

  void _hideMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  Widget _buildBabyOnly() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: GestureDetector(
                onTap: _onTap,
                onLongPress: () => _showMenu(context),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_jump, _spin]),
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, _jump.value),
                    child: Transform.rotate(angle: _spin.value, child: child),
                  ),
                  child: _BabyBody(
                    food: _serverFood,
                    love: _uiLove,
                    hearts: _hearts,
                    onHeartDone: _removeHeart,
                    speechText: _speechText,
                    speechVisible: _speechVisible,
                    partnerFloats: _partnerFloats,
                    onPartnerFloatDone: _removePartnerFloat, // ✅
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===== Build =====

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('未登入'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data();
        final partnerUid = userData?['partnerUid'] as String?;

        _currentReadCount = (userData?['read_message_count'] as int?) ?? 0;

        if (partnerUid == null) {
          return _buildBabyOnly();
        }

        if (myName == null) {
          _resolveMyName(
            myUid: uid,
            partnerUid: partnerUid,
            myUserData: userData,
          );
        }

        final ids = [uid, partnerUid]..sort();
        final relationshipId = ids.join('_');

        if (_relationshipId != relationshipId) {
          _relationshipId = relationshipId;
          _startMessagePolling(relationshipId, uid);
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('relationships')
              .doc(relationshipId)
              .snapshots(),
          builder: (context, relSnap) {
            final relData = relSnap.data?.data();
            final cd = relData?['countdown'];
            final serverLove = (relData?['love'] as int?) ?? 0;

            _serverFood = (relData?['food'] as int?) ?? 0;
            _serverLove = serverLove;

            _handleServerLove(serverLove);

            Widget countdown = const SizedBox.shrink();

            if (cd is Map && cd['enabled'] == true) {
              final ts = cd['targetAt'];
              if (ts is Timestamp) {
                final targetAt = ts.toDate();

                countdown = CountdownBanner(
                  key: ValueKey(targetAt.millisecondsSinceEpoch),
                  targetAt: targetAt,
                  eventTitle: cd['eventTitle'] ?? '活動',
                  onClose: () async {
                    await FirebaseFirestore.instance
                        .collection('relationships')
                        .doc(relationshipId)
                        .update({'countdown.enabled': false});
                  },
                );
              }
            }

            /// ⭐ 原本 UI ⭐
            return SizedBox.expand(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ① Baby
                  Positioned.fill(
                    child: Column(
                      children: [
                        const SizedBox(height: 120),
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: GestureDetector(
                                onTap: _onTap,
                                onLongPress: () => _showMenu(context),
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([_jump, _spin]),
                                  builder: (_, child) => Transform.translate(
                                    offset: Offset(0, _jump.value),
                                    child: Transform.rotate(
                                      angle: _spin.value,
                                      child: child,
                                    ),
                                  ),
                                  child: _BabyBody(
                                    food: _serverFood,
                                    love: _uiLove,
                                    hearts: const [],
                                    onHeartDone: (_) {},
                                    speechText: _speechText,
                                    speechVisible: _speechVisible,
                                    partnerFloats: const [],
                                    onPartnerFloatDone: (_) {},
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ② Countdown
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: UnconstrainedBox(
                        child: SizedBox(
                          height: 140,
                          child: Center(child: countdown),
                        ),
                      ),
                    ),
                  ),

                  // ③ 愛心 / float
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ..._hearts.map(
                            (h) => _HeartFly(
                              key: ValueKey(h.id),
                              startDx: h.dx,
                              fromPartner: h.fromPartner,
                              onDone: () => _removeHeart(h.id),
                            ),
                          ),
                          ..._partnerFloats.map(
                            (p) => _UserFloat(
                              key: ValueKey('pf_${p.id}'),
                              delta: p.delta,
                              startDx: p.dx,
                              photoUrl: p.photoUrl,
                              onDone: () => _removePartnerFloat(p.id),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ===== UI Components =====

class _BabyBody extends StatelessWidget {
  final int food;
  final int love;
  final List<_FloatingHeart> hearts;
  final void Function(int id) onHeartDone;
  final String? speechText; // ⭐ 新增
  final bool speechVisible;
  final List<_PartnerFloat> partnerFloats;

  const _BabyBody({
    required this.food,
    required this.love,
    required this.hearts,
    required this.onHeartDone,
    required this.speechText,
    required this.speechVisible,
    required this.partnerFloats,
    required this.onPartnerFloatDone, // ⭐ 新增
  });

  final void Function(int id) onPartnerFloatDone;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // const SizedBox(height: 120),
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 💬 對話框（在最上面）
            if (speechText != null)
              Positioned(
                top: -70,
                child: AnimatedOpacity(
                  opacity: speechVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  child: _SpeechBubble(text: speechText!),
                ),
              ),
            // 👶 原本的 baby
            Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(60),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(60),
                child: Image.asset('assets/images/1.png', fit: BoxFit.cover),
              ),
            ),

            ...hearts.map(
              (h) => _HeartFly(
                key: ValueKey(h.id),
                startDx: h.dx,
                fromPartner: h.fromPartner,
                onDone: () => onHeartDone(h.id),
              ),
            ),
            ...partnerFloats.map(
              (p) => _UserFloat(
                key: ValueKey('pf_${p.id}'),
                delta: p.delta,
                startDx: p.dx,
                photoUrl: p.photoUrl, // ⭐ 傳進來
                onDone: () => onPartnerFloatDone(p.id),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Text('飼料：$food  · 愛心：$love'),
        ),
      ],
    );
  }
}

class _FloatingHeart {
  final int id;
  final double dx;
  final bool fromPartner; // ⭐ 新增

  const _FloatingHeart({
    required this.id,
    required this.dx,
    required this.fromPartner,
  });
}

class _HeartFly extends StatefulWidget {
  final double startDx;
  final bool fromPartner; // ⭐ 新增
  final VoidCallback onDone;

  const _HeartFly({
    super.key,
    required this.startDx,
    required this.fromPartner, // ⭐
    required this.onDone,
  });

  @override
  State<_HeartFly> createState() => _HeartFlyState();
}

class _HeartFlyState extends State<_HeartFly>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _up;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _up = Tween(
      begin: 0.0,
      end: -120.0,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_ctrl);

    _fade = Tween(
      begin: 1.0,
      end: 0.0,
    ).chain(CurveTween(curve: Curves.easeIn)).animate(_ctrl);

    _scale = Tween(
      begin: 0.9,
      end: 1.2,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_ctrl);

    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Positioned(
        left: widget.startDx + 90,
        top: 250 + _up.value,
        child: Opacity(
          opacity: _fade.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Icon(
              Icons.favorite,
              size: 30,
              color: widget.fromPartner
                  ? const Color.fromARGB(255, 255, 119, 210) // 💙 對方
                  : Colors.pinkAccent, // 💗 自己
            ),
          ),
        ),
      ),
    );
  }
}

class CountdownBanner extends StatefulWidget {
  final DateTime targetAt;
  final String eventTitle;
  final VoidCallback onClose;

  const CountdownBanner({
    super.key,
    required this.targetAt,
    required this.eventTitle,
    required this.onClose,
  });

  @override
  State<CountdownBanner> createState() => _CountdownBannerState();
}

class _CountdownBannerState extends State<CountdownBanner>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  late Duration _remain;
  int _tapCount = 0;
  Timer? _tapWindow;
  bool _rainbowMode = false;
  late final AnimationController _rainbowCtrl;
  late final Animation<double> _rainbowShift;
  bool _rainbowUnlocked = false;
  bool _collapsed = true;
  int? _lastVibrateSecond;

  void _onBannerTap() {
    HapticFeedback.selectionClick();

    setState(() {
      _collapsed = !_collapsed;
    });

    // ⭐ 展開時 → 啟動彩虹
    if (!_collapsed) {
      _rainbowUnlocked = true; // 直接視為已解鎖
      _rainbowMode = true;
      _rainbowCtrl.repeat();
    } else {
      // ⭐ 縮小時 → 關彩虹
      _rainbowMode = false;
      _rainbowCtrl.stop();
    }
  }

  String _formatRemain(Duration d) {
    final totalSeconds = d.inSeconds;
    if (totalSeconds <= 0) return '0 秒';

    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;

    // ≥ 1 天
    if (days > 0) {
      return '$days 天 $hours 小時 $minutes 分';
    }

    // < 24 小時（顯示秒）
    if (hours > 0) {
      return '$hours 小時 $minutes 分 $seconds 秒';
    }

    // < 1 小時
    if (minutes > 0) {
      return '$minutes 分 $seconds 秒';
    }

    // < 1 分鐘
    return '$seconds 秒';
  }

  String _formatRemainInline(Duration d) {
    if (d.isNegative) return '0 秒';

    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;

    final parts = <String>[];
    if (days > 0) parts.add('$days 天');
    if (hours > 0 || parts.isNotEmpty) parts.add('$hours 時');
    if (minutes > 0 || parts.isNotEmpty) parts.add('$minutes 分');
    parts.add('$seconds 秒');

    return parts.join(' ');
  }

  @override
  void initState() {
    super.initState();
    _calc();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _calc());

    _rainbowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    _rainbowShift = Tween<double>(
      begin: 1.0, // 👉 從右邊開始
      end: -1.0, // 👉 往左流動
    ).animate(CurvedAnimation(parent: _rainbowCtrl, curve: Curves.linear));
  }

  void _calc() {
    final now = DateTime.now();
    final remain = widget.targetAt.difference(now);

    // 🟡 剩餘秒數（取整）
    final secondsLeft = remain.inSeconds;

    // 🔔 最後 60 秒：每秒震動一次
    if (secondsLeft <= 60 && secondsLeft >= 0) {
      HapticFeedback.mediumImpact(); // 輕
    }

    setState(() {
      _remain = remain;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _tapWindow?.cancel();
    _rainbowCtrl.dispose();
    super.dispose();
  }

  Widget _compactBox(BuildContext context, {required String text}) {
    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          return SizeTransition(
            sizeFactor: anim,
            axisAlignment: -1.0,
            child: FadeTransition(opacity: anim, child: child),
          );
        },
        child: _collapsed
            ? KeyedSubtree(
                key: const ValueKey('mini'),
                child: _MiniWrapper(child: _mini(context)),
              )
            : KeyedSubtree(
                key: const ValueKey('expanded'),
                child: _ExpandedWrapper(child: _expanded(context)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_remain.isNegative) {
      return _box(
        context,
        title: '時間到囉 🎉',
        content: '「${widget.eventTitle}」',
        extra: TextButton(
          onPressed: widget.onClose,
          child: const Text('關閉計時器'),
        ),
      );
    }

    return GestureDetector(
      onTap: _onBannerTap,
      // 移除外層 Container 的 width: double.infinity
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
          return Stack(
            alignment: Alignment.center, // 關鍵：對齊中心
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, anim) {
          return SizeTransition(
            sizeFactor: anim,
            axisAlignment: 0.0,
            axis: Axis.horizontal, // 水平展開
            child: FadeTransition(opacity: anim, child: child),
          );
        },
        child: _collapsed
            ? _MiniWrapper(key: const ValueKey('mini'), child: _mini(context))
            : _ExpandedWrapper(
                key: const ValueKey('expanded'),
                child: _expanded(context),
              ),
      ),
    );
  }

  Widget _mini(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, size: 14),
          const SizedBox(width: 4),
          Text(
            _formatRemain(_remain),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _expanded(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer, size: 18),
              const SizedBox(width: 6),
              Text('距離「${widget.eventTitle}」還有'),
            ],
          ),
          const SizedBox(height: 6),
          _rainbowMode
              ? _rainbowText(
                  _formatRemainInline(_remain),
                  Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Text(
                  _formatRemainInline(_remain),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _rainbowText(String text, TextStyle? style) {
    return AnimatedBuilder(
      animation: _rainbowShift,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [
                Colors.red,
                Colors.orange,
                Colors.yellow,
                Colors.green,
                Colors.blue,
                Colors.purple,
              ],
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              tileMode: TileMode.mirror,
            ).createShader(
              Rect.fromLTWH(
                bounds.width * _rainbowShift.value,
                0,
                bounds.width,
                bounds.height,
              ),
            );
          },
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: style?.copyWith(color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _box(
    BuildContext context, {
    required String title,
    required String content,
    Widget? extra,
  }) {
    final radius = BorderRadius.circular(16);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _onBannerTap,
        borderRadius: radius,

        // 🚫 關掉所有漣漪與高亮效果
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,

        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: radius,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer, size: 18),
                  const SizedBox(width: 6),
                  Text(title),
                ],
              ),
              const SizedBox(height: 6),

              // 🌈 彩虹 / 一般文字
              _rainbowMode
                  ? _rainbowText(
                      content,
                      Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Text(
                      content,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),

              if (extra != null) ...[const SizedBox(height: 8), extra],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeechBubble extends StatefulWidget {
  final String text;

  const _SpeechBubble({required this.text});

  @override
  State<_SpeechBubble> createState() => _SpeechBubbleState();
}

class _SpeechBubbleState extends State<_SpeechBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _scale;
  Timer? _loopTimer;

  bool _firstJump = true;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _setupAnimation(); // ⭐ 設定第一次動畫
    _ctrl.forward(from: 0);

    // ⭐ 每 2 秒跳一次（之後是小跳）
    _loopTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;

      _firstJump = false; // ⭐ 後續都變小跳
      _setupAnimation();
      _ctrl.forward(from: 0);
    });
  }

  void _setupAnimation() {
    if (_firstJump) {
      // 🎉 第一次大跳
      _scale = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(
            begin: 0.7,
            end: 1.2,
          ).chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 60,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.2,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 40,
        ),
      ]).animate(_ctrl);
    } else {
      // 💗 小跳
      _scale = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0,
            end: 1.10,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.10,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 50,
        ),
      ]).animate(_ctrl);
    }
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color.fromARGB(255, 255, 117, 186),
                    Color.fromARGB(255, 230, 6, 126),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.text,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          Transform.translate(
            offset: const Offset(0, -12),
            child: const Icon(
              Icons.arrow_drop_down,
              size: 45,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerFloat {
  final int id;
  final int delta;
  final double dx;
  final String? photoUrl;

  const _PartnerFloat({
    required this.id,
    required this.delta,
    required this.dx,
    required this.photoUrl,
  });
}

class _UserFloat extends StatefulWidget {
  final int delta;
  final double startDx;
  final VoidCallback onDone;
  final String? photoUrl;

  const _UserFloat({
    super.key,
    required this.delta,
    required this.startDx,
    required this.photoUrl,
    required this.onDone,
  });

  @override
  State<_UserFloat> createState() => _UserFloatState();
}

class _UserFloatState extends State<_UserFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _up;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    );

    _up = Tween(
      begin: 0.0,
      end: -110.0,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_ctrl);

    _fade = Tween(
      begin: 1.0,
      end: 0.0,
    ).chain(CurveTween(curve: Curves.easeIn)).animate(_ctrl);

    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Positioned(
        left: widget.startDx + 90,
        top: 150 + _up.value,
        child: Opacity(
          opacity: _fade.value,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🧑 對方頭貼
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: widget.photoUrl != null
                    ? NetworkImage(widget.photoUrl!)
                    : const AssetImage('assets/images/partner.png'),
              ),
              const SizedBox(width: 6),

              // ❤️ +N
              Text(
                '+${widget.delta}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.pinkAccent,
                ),
              ),

              const SizedBox(width: 4),
              const Icon(Icons.favorite, color: Colors.pinkAccent, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniWrapper extends StatelessWidget {
  final Widget child;
  const _MiniWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      // 移除 IntrinsicWidth，改用合理的 padding 即可
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20), // 圓角大一點比較像膠囊
      ),
      child: child,
    );
  }
}

class _ExpandedWrapper extends StatelessWidget {
  final Widget child;
  const _ExpandedWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340, // ⭐ 明確指定
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }
}
