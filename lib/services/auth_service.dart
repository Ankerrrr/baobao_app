import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final _db = FirebaseFirestore.instance;

  /// 登入成功後同步使用者資料
  static Future<void> syncUserProfile() async {
    final user = FirebaseAuth.instance.currentUser!;
    final ref = _db.collection('users').doc(user.uid);

    await ref.set({
      'displayName': user.displayName ?? '',
      'email': user.email ?? '',
      'photoURL': user.photoURL ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
