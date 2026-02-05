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
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance
        .collection('relationships')
        .doc(relationshipId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      final foodEarnedBy = Map<String, dynamic>.from(
        data['foodEarnedBy'] ?? {},
      );
      final myEarned = (foodEarnedBy[uid] as int?) ?? 0;

      tx.update(ref, {
        if (pendingLove > 0) 'love': FieldValue.increment(pendingLove),

        if (earnedFood > 0) 'food': FieldValue.increment(earnedFood),

        if (earnedFood > 0) 'foodEarnedBy.$uid': myEarned + earnedFood,

        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
