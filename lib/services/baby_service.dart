import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BabyService {
  static final _db = FirebaseFirestore.instance;

  /// 增加愛心（雙方共用）
  static Future<void> addLove() async {
    final user = FirebaseAuth.instance.currentUser!;
    final myRef = _db.collection('users').doc(user.uid);

    await _db.runTransaction((tx) async {
      final mySnap = await tx.get(myRef);
      final myData = mySnap.data()!;
      final partnerUid = myData['partnerUid'];

      if (partnerUid == null) {
        throw Exception('尚未綁定共養對象');
      }

      final partnerRef = _db.collection('users').doc(partnerUid);

      final currentLove = (myData['baby']?['love'] as int?) ?? 0;

      final nextLove = currentLove + 1;

      // 同步寫給自己 + 對方
      tx.update(myRef, {
        'baby.love': nextLove,
        'baby.updatedAt': FieldValue.serverTimestamp(),
      });

      tx.update(partnerRef, {
        'baby.love': nextLove,
        'baby.updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
