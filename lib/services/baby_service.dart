import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'dart:math';

class BabyService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> syncLoveAndFood({
    required String relationshipId,
    required int pendingLove,
    required int earnedFood,
  }) async {
    print('🔥 syncLoveAndFood called');
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance
        .collection('relationships')
        .doc(relationshipId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      final hasLove = data['love'] is int;
      final hasFood = data['food'] is int;
      final hasFoodMap = data['foodEarnedBy'] is Map;

      // ⭐ ① 補齊缺失欄位（不 return）
      if (!hasLove || !hasFood || !hasFoodMap) {
        tx.set(ref, {
          if (!hasLove) 'love': 0,
          if (!hasFood) 'food': 0,
          if (!hasFoodMap) 'foodEarnedBy': {},
          'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // ⭐ ② 沒有要同步的，直接結束
      if (pendingLove <= 0 && earnedFood <= 0) return;

      final foodEarnedBy = Map<String, dynamic>.from(
        data['foodEarnedBy'] ?? {},
      );
      final myEarned = (foodEarnedBy[uid] as int?) ?? 0;

      // ⭐ ③ 正常累加
      tx.update(ref, {
        if (pendingLove > 0) 'love': FieldValue.increment(pendingLove),
        if (earnedFood > 0) 'food': FieldValue.increment(earnedFood),
        if (earnedFood > 0) 'foodEarnedBy.$uid': myEarned + earnedFood,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
