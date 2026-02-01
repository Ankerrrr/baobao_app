import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class BabyService {
  static final _db = FirebaseFirestore.instance;

  /// 增加愛心（雙方共用）
  static Future<int> syncLove(int _pendingTapCount) async {
    final user = FirebaseAuth.instance.currentUser!;
    final myRef = _db.collection('users').doc(user.uid);

    return await _db.runTransaction<int>((tx) async {
      // 1️⃣ 讀自己的資料
      final mySnap = await tx.get(myRef);
      final myData = mySnap.data();

      if (myData == null) {
        throw Exception('找不到自己的使用者資料');
      }

      final partnerUid = myData['partnerUid'];
      if (partnerUid == null || partnerUid is! String) {
        throw Exception('尚未綁定共養對象');
      }

      final partnerRef = _db.collection('users').doc(partnerUid);

      // 2️⃣ 讀對方資料
      final partnerSnap = await tx.get(partnerRef);
      final partnerData = partnerSnap.data();

      if (partnerData == null) {
        throw Exception('找不到對方的使用者資料');
      }

      // 3️⃣ 取三個值（都保證是 int）
      final myLove = (myData['baby']?['love'] as int?) ?? 0;
      final partnerLove = (partnerData['baby']?['love'] as int?) ?? 0;

      final baseLove = max(myLove, partnerLove);
      final nextLove = baseLove + _pendingTapCount; // ⭐ 加上這批點擊數

      // 5️⃣ 同步寫回雙方
      tx.update(myRef, {
        'baby.love': nextLove,
        'baby.updatedAt': FieldValue.serverTimestamp(),
      });

      tx.update(partnerRef, {
        'baby.love': nextLove,
        'baby.updatedAt': FieldValue.serverTimestamp(),
      });

      // 6️⃣ 回傳同步後的 love
      _pendingTapCount = 0;
      return nextLove;
    });
  }
}
