import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EconomyService {
  EconomyService._();
  static final instance = EconomyService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// 🔥 消耗飼料（通用）
  ///
  /// - cost: 要扣的飼料數（例如 2）
  /// - onSuccessTx: 扣成功後要做的事（同一個 transaction）
  ///
  Future<void> spendFood({
    required String relationshipId,
    required int cost,
    required Future<void> Function(Transaction tx, DocumentReference relRef)
    onSuccessTx,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('not logged in');
    }

    final relRef = _db.collection('relationships').doc(relationshipId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(relRef);
      if (!snap.exists) {
        throw Exception('relationship not found');
      }

      final data = snap.data()!;
      final int food = (data['food'] as int?) ?? 0;

      // ❌ 飼料不足
      if (food < cost) {
        throw Exception('not enough food');
      }

      // 1️⃣ 扣飼料
      tx.update(relRef, {
        'food': FieldValue.increment(-cost),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2️⃣ 執行成功後行為（例如：送通知）
      await onSuccessTx(tx, relRef);
    });
  }
}
