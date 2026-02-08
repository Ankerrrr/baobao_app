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

  String _timeGreeting() {
    final hour = DateTime.now().hour;

    if (hour >= 5 && hour < 11) {
      return '早安～開心一整天';
    } else if (hour >= 11 && hour < 17) {
      return '午安～記得吃飯喔';
    } else if (hour >= 17 && hour < 22) {
      return '晚ㄤ～好好休息呦 ';
    } else {
      return '該睡覺ㄌ~';
    }
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

  void _say(String text, {Duration duration = const Duration(seconds: 10)}) {
    _speechTimer?.cancel();

    setState(() {
      _speechText = text;
      _speechVisible = true; // ⭐ 顯示
    });

    _speechTimer = Timer(duration, () async {
      if (!mounted) return;

      // ⭐ 先淡出
      setState(() {
        _speechVisible = false;
      });

      // ⭐ 等動畫結束再真的移除
      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;
      setState(() {
        _speechText = null;
      });
    });
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
    _hideMenu();
    super.dispose();
  }

  // ===== Actions =====

  void _onTap() {
    if (_jumpCtrl.isAnimating) return;

    _jumpCtrl.forward(from: 0);
    HapticFeedback.heavyImpact();

    _unsyncedTaps++;
    _spawnHeart();
    _queueSelfFloat(1);

    _tapForFood++;

    if (_tapForFood % 50 == 0) {
      _say('嘿嘿～');
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
            onTap: _hideMenu,
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
                    mood: _mood,
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
        // final serverLove = (userData?['baby']?['love'] as int?) ?? 0;
        // _handleServerLove(serverLove);

        final partnerUid = userData?['partnerUid'] as String?;
        if (partnerUid == null) {
          // ❌ 沒綁定 → 不顯示倒數
          return _buildBabyOnly();
        }

        FirebaseFirestore.instance
            .collection('users')
            .doc(partnerUid)
            .get()
            .then((snap) {
              final data = snap.data();
              final url = data?['photoURL'] as String?;
              if (mounted && url != _partnerPhotoUrl) {
                setState(() {
                  _partnerPhotoUrl = url;
                });
              }
            });

        final ids = [uid, partnerUid]..sort();
        final relationshipId = ids.join('_');

        // ⭐⭐⭐ 關鍵中的關鍵
        if (_relationshipId != relationshipId) {
          _relationshipId = relationshipId;
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('relationships')
              .doc(relationshipId)
              .snapshots(),
          builder: (context, relSnap) {
            final relData = relSnap.data?.data();
            final cd = relSnap.data?.data()?['countdown'];
            final serverLove = (relData?['love'] as int?) ?? 0;

            _serverFood = (relData?['food'] as int?) ?? 0;
            _serverLove = (relData?['love'] as int?) ?? 0;

            _handleServerLove(serverLove);

            Widget countdown = const SizedBox.shrink();

            if (cd is Map && cd['enabled'] == true) {
              final ts = cd['targetAt'];

              if (ts is Timestamp) {
                final targetAt = ts.toDate(); // ✅ Firestore → Local DateTime

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

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 340, // ⭐ 你要的寬度（重點）
                      maxHeight: 150,
                    ),
                    child: countdown,
                  ),
                ),

                // 👶 原本寶寶互動（完全不動）
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
                            mood: _mood,
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
          },
        );
      },
    );
  }

  Future<void> _feedBaby(String relationshipId) async {
    if (_serverFood <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('沒有飼料了 😢')));
      return;
    }

    HapticFeedback.heavyImpact();

    for (int i = 0; i < 5; i++) {
      _spawnHeart();
    }

    await FirebaseFirestore.instance
        .collection('relationships')
        .doc(relationshipId)
        .update({
          'food': FieldValue.increment(-1),
          'love': FieldValue.increment(10), // 🎁 餵食回饋
        });
  }
}

// ===== UI Components =====

class _BabyBody extends StatelessWidget {
  final String mood;
  final int love;
  final List<_FloatingHeart> hearts;
  final void Function(int id) onHeartDone;
  final String? speechText; // ⭐ 新增
  final bool speechVisible;
  final List<_PartnerFloat> partnerFloats;

  const _BabyBody({
    required this.mood,
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
          child: Text('心情：$mood · 愛心：$love'),
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
        left: widget.startDx + 20,
        top: -20 + _up.value,
        child: Opacity(
          opacity: _fade.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Icon(
              Icons.favorite,
              size: 30,
              color: widget.fromPartner
                  ? const Color.fromARGB(255, 96, 44, 66) // 💙 對方
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
    if (secondsLeft <= 60 && secondsLeft > 10) {
      HapticFeedback.mediumImpact(); // 輕
    } else if (secondsLeft <= 10) {
      HapticFeedback.heavyImpact(); // 中
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
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ⏱ 時鐘 icon（縮小專用）
            const Icon(Icons.timer, size: 18),
            const SizedBox(width: 6),

            // ⏳ 倒數文字（單列）
            Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
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
      child: AnimatedSize(
        duration: const Duration(milliseconds: 50),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: _collapsed
              // 🔽 縮小（一定要有 key）
              ? KeyedSubtree(
                  key: const ValueKey('collapsed'),
                  child: _compactBox(context, text: _formatRemain(_remain)),
                )
              // 🔼 展開（一定要有 key）
              : KeyedSubtree(
                  key: const ValueKey('expanded'),
                  child: _box(
                    context,
                    title: '距離「${widget.eventTitle}」還有',
                    content: _formatRemainInline(_remain),
                  ),
                ),
        ),
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

class _SpeechBubble extends StatelessWidget {
  final String text;

  const _SpeechBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 💬 泡泡本體
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
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
              text,
              style: const TextStyle(
                fontSize: 20,
                color: Color.fromARGB(255, 155, 119, 0),
              ),
            ),
          ),

          // 🔽 箭頭（往上貼）
          Transform.translate(
            offset: const Offset(0, -12), // ⭐ 關鍵：往上推
            child: Icon(Icons.arrow_drop_down, size: 45, color: Colors.white),
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
        left: widget.startDx + 20,
        top: -40 + _up.value,
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
