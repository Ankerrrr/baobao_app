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

  Timer? _timer;

  /// 🚀 初始化（App 啟動時呼叫）
  void init() {
    WidgetsBinding.instance.addObserver(this);

    // 啟動時立刻上傳一次
    _uploadBattery();

    // 每 5 分鐘更新一次（可自行調）
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _uploadBattery(),
    );
  }

  /// 🧹 關閉（登出 / App 關閉）
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
  }

  /// 📱 App 前後景切換（很重要）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前景，立刻更新
      _uploadBattery();
    }
  }

  /// 🔋 實際上傳電池資料
  Future<void> _uploadBattery() async {
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

      debugPrint('🔋 battery uploaded: $level%, charging=$isCharging');
    } catch (e) {
      debugPrint('❌ battery upload failed: $e');
    }
  }
}
