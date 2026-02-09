import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../app_runtime_state.dart';

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
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null) return;

        debugPrint('🔔 local notification tapped → $payload');

        // payload = relationshipId
        AppRuntimeState.pendingOpenRelationshipId = payload;
      },
    );

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

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _saveMyToken(token);
    }
  }

  // ===== 前景通知 =====
  void _onForegroundMessage(RemoteMessage msg) {
    final notif = msg.notification;
    final title = notif?.title ?? '新訊息';
    final body = notif?.body;
    final relationshipId = msg.data['relationshipId'];

    if (body == null || relationshipId == null) return;

    // 已在聊天室 → 不顯示
    if (AppRuntimeState.currentChatRelationshipId == relationshipId) {
      return;
    }

    showLocal(title: title, body: body, relationshipId: relationshipId);
  }

  Future<void> showLocal({
    required String title,
    required String body,
    required String relationshipId,
  }) async {
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
      payload: relationshipId, // ⭐⭐⭐ 關鍵
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

    // 跟 MessagePage 一樣：從 users 讀 partnerUid
    final mySnap = await _db.collection('users').doc(uid).get();
    final partnerUid = mySnap.data()?['partnerUid'] as String?;
    if (partnerUid == null) return;

    final relRef = _db.collection('relationships').doc(relationshipId);
    if (!(await relRef.get()).exists) return;

    await relRef.collection('notifications').add({
      'fromUid': uid,
      'toUid': partnerUid,
      'title': title,
      'text': text,
      'sent': false,
      'retryCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== ⭐ 對外提供「通知被點擊」callback =====
  void setupNotificationTapHandler({
    required void Function(String relationshipId) onOpenMessage,
  }) {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTap(message, onOpenMessage);
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleTap(message, onOpenMessage);
      }
    });
  }

  void _handleTap(
    RemoteMessage message,
    void Function(String relationshipId) onOpenMessage,
  ) {
    final relationshipId = message.data['relationshipId'];
    if (relationshipId == null) return;

    debugPrint('🔔 notification tapped → $relationshipId');
    onOpenMessage(relationshipId);
  }
}
