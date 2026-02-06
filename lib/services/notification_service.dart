// services/notification_service.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _local = FlutterLocalNotificationsPlugin();

  // ===== 初始化 =====
  Future<void> init() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _local.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      'baby_channel',
      '寶寶通知',
      description: '你兄弟的訊息',
      importance: Importance.max,
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveMyToken);

    // ⭐ 主動存一次 token（非常重要）
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _saveMyToken(token);
    }
  }

  // ===== 前景通知 =====
  void _onForegroundMessage(RemoteMessage msg) {
    final data = msg.data;

    final title = data['title'] ?? '新訊息';
    final body = data['body'];

    if (body == null || body.toString().isEmpty) return;

    showLocal(title: title.toString(), body: body.toString());
  }

  Future<void> showLocal({required String title, required String body}) async {
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'baby_channel',
          '寶寶通知',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  // ===== 儲存 token =====
  Future<void> _saveMyToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      'fcmToken': token,
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('✅ FCM token saved');
  }

  // ===== 寫入通知任務（給 Cloud Function 用）=====
  Future<void> sendToPartner({
    required String relationshipId,
    required String text,
    required String title,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final relRef = _db.collection('relationships').doc(relationshipId);
    final relSnap = await relRef.get();
    if (!relSnap.exists) return;

    final List<String> members = List<String>.from(relSnap.data()!['members']);
    final partnerUid = members.firstWhere((e) => e != uid);

    await relRef.collection('notifications').add({
      'fromUid': uid,
      'toUid': partnerUid,
      'title': title, // ⭐ 通知標題（暱稱）
      'text': text, // ⭐ 一定要叫 text
      'sent': false,
      'retryCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    debugPrint('📨 notification queued → $partnerUid');
  }
}
