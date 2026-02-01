import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:baobao/widgets/rainbow_menu.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:baobao/services/baby_service.dart';

class InteractiveBaby extends StatefulWidget {
  const InteractiveBaby({super.key});

  @override
  State<InteractiveBaby> createState() => _InteractiveBabyState();
}

class _InteractiveBabyState extends State<InteractiveBaby>
    with TickerProviderStateMixin {
  // 跳躍動畫
  late final AnimationController _ctrl;
  late final Animation<double> _jump;

  // 旋轉動畫（成就觸發）
  late final AnimationController _spinCtrl;
  late final Animation<double> _spin;

  int _pendingTapCount = 0; // 尚未同步的 tap
  Offset _offset = Offset.zero;
  String _mood = '開心';
  int _love = 0;
  int _lastKnownPending = 0;

  OverlayEntry? _menuEntry;

  final List<_FloatingHeart> _hearts = [];
  int _heartId = 0;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _jump = Tween<double>(
      begin: 0,
      end: -18,
    ).chain(CurveTween(curve: Curves.easeOutBack)).animate(_ctrl);

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _spin = Tween<double>(
      begin: 0,
      end: 2 * pi,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_spinCtrl);
  }

  @override
  @override
  void dispose() {
    _tapTimer?.cancel();
    _syncTimer?.cancel();

    if (_pendingTapCount > 0) {
      BabyService.syncLove(_pendingTapCount);
    }

    _spinCtrl.dispose();
    _hideMenu();
    _ctrl.dispose();
    super.dispose();
  }

  void _spawnHeart() {
    final id = _heartId++;
    final dx = Random().nextDouble() * 80 - 40; // 左右飄 (-40 ~ +40)
    setState(() => _hearts.add(_FloatingHeart(id: id, dx: dx)));
  }

  void _removeHeart(int id) {
    if (!mounted) return;
    setState(() => _hearts.removeWhere((h) => h.id == id));
  }

  void _triggerSpin() {
    if (_spinCtrl.isAnimating) return;
    HapticFeedback.heavyImpact();
    _spinCtrl.forward(from: 0);
  }

  void pendingTapCountSetZero() {
    _pendingTapCount = 0; // 尚未同步的 tap = 0;
  }

  int _tapCount = 0;
  Timer? _tapTimer;

  Timer? _syncTimer;

  int _displayLove = 0; // 畫面上顯示的 love（不倒退）
  int _lastServerLove = 0; // 可選：記錄 serverLove（debug 用）
  static const Duration _syncInterval = Duration(seconds: 2);

  void _countTapForAchievement() {
    final Random _rng = Random();

    // 第一次點：開一個 10 秒窗口
    _tapTimer ??= Timer(const Duration(seconds: 10), () {
      _tapCount = 0;
      _tapTimer = null;
    });

    if (_tapCount >= 15) {
      _tapCount = 0;
      _tapTimer?.cancel();
      _tapTimer = null;

      // ⭐ 隨機機率觸發旋轉
      const double spinChance = 0.5;
      if (_rng.nextDouble() < spinChance) {
        _triggerSpin();
      }
    }
  }

  void _scheduleSync() {
    if (_syncTimer != null) return;

    _syncTimer = Timer(_syncInterval, () async {
      final tapsToSync = _pendingTapCount;
      _syncTimer = null;

      if (tapsToSync <= 0) return;

      try {
        await BabyService.syncLove(tapsToSync);

        if (mounted) {
          setState(() {
            _pendingTapCount -= tapsToSync;
            _lastKnownPending = tapsToSync; // ⭐ 記住：這次是我自己 sync 的
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('同步愛心失敗：$e')));
        }
      }
    });
  }

  Future<void> _onTap() async {
    if (_ctrl.isAnimating) return;
    _ctrl.forward(from: 0);

    _tapCount++;
    _pendingTapCount++; // ⭐ 累積尚未同步的點擊

    _spawnHeart();
    HapticFeedback.heavyImpact();

    _countTapForAchievement();

    _scheduleSync(); // ⭐ 不直接 sync
  }

  void _showMenu(BuildContext babyCtx) {
    final box = babyCtx.findRenderObject() as RenderBox;
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
            onTap: () {
              _hideMenu();
            },
          ),
          ArcMenuItem(
            icon: Icons.favorite,
            label: '討摸摸',
            onTap: () {
              _hideMenu();
            },
          ),
          ArcMenuItem(
            icon: Icons.question_answer,
            label: '問答',
            onTap: () {
              _hideMenu();
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('未登入'));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final serverLove = (data?['baby']?['love'] as int?) ?? 0;
        final int serverDelta = serverLove - _lastServerLove;

        final int externalDelta = max(0, serverDelta - _lastKnownPending);

        if (externalDelta > 0 && externalDelta < 30) {
          for (int i = 0; i < externalDelta; i++) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _spawnHeart();
            });
          }
        }

        // reset
        _lastKnownPending = 0;
        _lastServerLove = serverLove;

        // optimistic 顯示值
        final optimistic = serverLove + _pendingTapCount;

        // ⭐ 防止顯示倒退
        if (optimistic > _displayLove) {
          _displayLove = optimistic;
        }

        final love = _displayLove;

        return LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: Builder(
                builder: (babyCtx) => GestureDetector(
                  onTap: _onTap,
                  onLongPress: () => _showMenu(babyCtx),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_jump, _spin]),
                    builder: (context, child) {
                      return Transform.translate(
                        offset: _offset + Offset(0, _jump.value),
                        child: Transform.rotate(
                          angle: _spin.value,
                          child: child,
                        ),
                      );
                    },
                    child: _BabyBody(
                      mood: _mood,
                      love: love,
                      hearts: _hearts,
                      onHeartDone: _removeHeart,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

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
        const SizedBox(height: 120),

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
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(60),
                child: Transform.scale(
                  scale: 1.1,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: Image.asset('assets/images/1.png'),
                  ),
                ),
              ),
            ),

            ...hearts.map((h) {
              return _HeartFly(
                key: ValueKey(h.id),
                startDx: h.dx,
                onDone: () => onHeartDone(h.id),
              );
            }),
          ],
        ),

        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Text('心情：$mood  ·  愛心：$love'),
        ),
      ],
    );
  }
}

class _FloatingHeart {
  final int id;
  final double dx;
  _FloatingHeart({required this.id, required this.dx});
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

    _up = Tween<double>(
      begin: 0,
      end: -120,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_ctrl);

    _fade = Tween<double>(
      begin: 1,
      end: 0,
    ).chain(CurveTween(curve: Curves.easeIn)).animate(_ctrl);

    _scale = Tween<double>(
      begin: 0.9,
      end: 1.2,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_ctrl);

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDone();
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Positioned(
          left: widget.startDx,
          top: -20 + _up.value,
          child: Opacity(
            opacity: _fade.value,
            child: Transform.scale(
              scale: _scale.value,
              child: const Text('❤️', style: TextStyle(fontSize: 30)),
            ),
          ),
        );
      },
    );
  }
}
