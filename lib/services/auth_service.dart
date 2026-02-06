import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthService {
  static final _db = FirebaseFirestore.instance;

  /// 登入成功後同步使用者資料（含 FCM token）
  static Future<void> syncUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = _db.collection('users').doc(user.uid);

    // 1️⃣ 取得 FCM token
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      // token 失敗不影響登入流程
      fcmToken = null;
    }

    // 2️⃣ 同步到 Firestore（merge，不會蓋掉其他欄位）
    await ref.set({
      'displayName': user.displayName ?? '',
      'email': user.email ?? '',
      'photoURL': user.photoURL ?? '',
      if (fcmToken != null) 'fcmToken': fcmToken,
      if (fcmToken != null) 'fcmUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
