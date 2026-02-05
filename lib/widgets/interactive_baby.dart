import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baobao/widgets/rainbow_menu.dart';
import 'package:baobao/services/baby_service.dart';

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

  String? _relationshipId;

  // Love / Sync
  int _unsyncedTaps = 0;
  int _lastSelfSynced = 0;
  int _lastServerLove = 0;
  int _displayLove = 0;

  static const _syncInterval = Duration(seconds: 2);
  Timer? _syncTimer;

  // Achievement
  int _tapCount = 0;
  Timer? _tapWindow;

  // UI
  OverlayEntry? _menuEntry;
  final List<_FloatingHeart> _hearts = [];
  int _heartId = 0;

  final String _mood = '開心';

  @override
  void initState() {
    super.initState();

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

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) {
        final partnerUid = doc.data()?['partnerUid'];
        if (partnerUid != null) {
          final ids = [uid, partnerUid]..sort();
          setState(() {
            _relationshipId = ids.join('_');
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _tapWindow?.cancel();
    _syncTimer?.cancel();

    if (_unsyncedTaps > 0) {
      BabyService.syncLove(_unsyncedTaps);
    }

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
    if (_syncTimer != null) return;

    _syncTimer = Timer(_syncInterval, () async {
      final toSync = _unsyncedTaps;
      _syncTimer = null;

      if (toSync <= 0) return;

      await BabyService.syncLove(toSync);

      if (!mounted) return;
      setState(() {
        _unsyncedTaps -= toSync;
        _lastSelfSynced = toSync;
      });
    });
  }

  void _handleServerLove(int serverLove) {
    final serverDelta = serverLove - _lastServerLove;
    final externalDelta = max(0, serverDelta - _lastSelfSynced);

    if (externalDelta > 0 && externalDelta < 30) {
      for (int i = 0; i < externalDelta; i++) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _spawnHeart();
        });
      }
    }

    _lastSelfSynced = 0;
    _lastServerLove = serverLove;

    final optimistic = serverLove + _unsyncedTaps;
    _displayLove = max(_displayLove, optimistic);
  }

  // ===== Hearts =====

  void _spawnHeart() {
    final id = _heartId++;
    final dx = Random().nextDouble() * 100 - 40;
    setState(() {
      _hearts.add(_FloatingHeart(id: id, dx: dx));
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
          ArcMenuItem(
            icon: Icons.question_answer,
            label: '問答',
            textColor: Colors.lightBlueAccent,
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
                    love: _displayLove,
                    hearts: _hearts,
                    onHeartDone: _removeHeart,
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
        final serverLove = (userData?['baby']?['love'] as int?) ?? 0;
        _handleServerLove(serverLove);

        final partnerUid = userData?['partnerUid'] as String?;
        if (partnerUid == null) {
          // ❌ 沒綁定 → 不顯示倒數
          return _buildBabyOnly();
        }

        final ids = [uid, partnerUid]..sort();
        final relationshipId = ids.join('_');

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('relationships')
              .doc(relationshipId)
              .snapshots(),
          builder: (context, relSnap) {
            final cd = relSnap.data?.data()?['countdown'];

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
                            love: _displayLove,
                            hearts: _hearts,
                            onHeartDone: _removeHeart,
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
}

// ===== UI Components =====

class _BabyBody extends StatelessWidget {
  final String mood;
  final int love;
  final List<_FloatingHeart> hearts;
  final void Function(int id) onHeartDone;

  const _BabyBody({
    required this.mood,
    required this.love,
    required this.hearts,
    required this.onHeartDone,
  });

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
                onDone: () => onHeartDone(h.id),
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
  const _FloatingHeart({required this.id, required this.dx});
}

class _HeartFly extends StatefulWidget {
  final double startDx;
  final VoidCallback onDone;

  const _HeartFly({super.key, required this.startDx, required this.onDone});

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
            child: const Text('❤️', style: TextStyle(fontSize: 30)),
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

  void _onBannerTap() {
    // ⭐ 已解鎖彩虹 → 直接切換 ON / OFF
    if (_rainbowUnlocked) {
      setState(() {
        _rainbowMode = !_rainbowMode;
      });

      if (_rainbowMode) {
        _rainbowCtrl.repeat(); // 開
      } else {
        _rainbowCtrl.stop(); // 關
      }

      HapticFeedback.selectionClick();
      return;
    }

    // ===== 尚未解鎖：成就判定 =====

    _tapWindow ??= Timer(const Duration(seconds: 10), () {
      _tapCount = 0;
      _tapWindow = null;
    });

    _tapCount++;

    if (_tapCount >= 1) {
      _tapCount = 0;
      _tapWindow?.cancel();
      _tapWindow = null;

      setState(() {
        _rainbowUnlocked = true;
        _rainbowMode = true;
      });

      _rainbowCtrl.repeat();
      HapticFeedback.heavyImpact(); // 🎉 解鎖震動
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
    debugPrint(
      'now=$now (${now.isUtc}) '
      'target=${widget.targetAt} (${widget.targetAt.isUtc}) '
      'diff=${widget.targetAt.difference(now).inSeconds}',
    );

    setState(() {
      _remain = widget.targetAt.difference(now);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _tapWindow?.cancel();
    _rainbowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remain.isNegative) {
      return _box(
        context,
        title: '活動開始囉 🎉',
        content: '「${widget.eventTitle}」',
        extra: TextButton(
          onPressed: widget.onClose,
          child: const Text('關閉計時器'),
        ),
      );
    }

    return GestureDetector(
      onTap: _onBannerTap,
      child: _box(
        context,
        title: '距離「${widget.eventTitle}」還有',
        content: _formatRemain(_remain),
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
        splashFactory: InkRipple.splashFactory,
        splashColor: Colors.white24,
        highlightColor: Colors.white10,
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

              // 🌈 這裡維持你原本的彩虹 / 一般文字切換
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
