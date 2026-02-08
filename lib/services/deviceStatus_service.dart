import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

class DeviceStatusService with WidgetsBindingObserver {
  DeviceStatusService._();
  static final instance = DeviceStatusService._();

  final _battery = Battery();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _inited = false;
  Timer? _timer;

  DateTime? _lastUpload;

  /// 🚀 初始化（App 啟動時呼叫）
  void init() {
    if (_inited) return;
    _inited = true;

    WidgetsBinding.instance.addObserver(this);

    // ⭐ Timer 也走節流
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _maybeUpload(reason: 'timer'),
    );

    _maybeUpload(reason: 'init');
  }

  /// 🧹 關閉（登出 / App 關閉）
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _inited = false;
  }

  /// 📱 前後景切換（高頻事件 → 必須節流）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeUpload(reason: 'resume');
    }
  }

  /// 🚦 全部來源統一走這裡
  Future<void> _maybeUpload({required String reason}) async {
    final now = DateTime.now();

    // ⛔ 1 分鐘內最多一次（你可改 30 秒 / 5 分鐘）
    if (_lastUpload != null &&
        now.difference(_lastUpload!) < const Duration(seconds: 20)) {
      return;
    }

    _lastUpload = now;
    await _uploadBattery(reason: reason);
  }

  /// 🔋 真正上傳（不管電池有沒有變，都會傳）
  Future<void> _uploadBattery({required String reason}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final isCharging =
          state == BatteryState.charging || state == BatteryState.full;

      await _db.collection('users').doc(user.uid).set({
        'battery': {
          'level': level,
          'isCharging': isCharging,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      debugPrint(
        '🔋 battery uploaded ($reason): $level%, charging=$isCharging',
      );
    } catch (e) {
      debugPrint('❌ battery upload failed: $e');
    }
  }
}
