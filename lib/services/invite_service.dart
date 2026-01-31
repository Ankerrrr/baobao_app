import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InviteService {
  static final _db = FirebaseFirestore.instance;

  static String _generateCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// 建立邀請碼
  static Future<String> createInviteCode() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userDoc = await _db.collection('users').doc(uid).get();
    if (userDoc.data()?['partnerUid'] != null) {
      throw Exception('你已經有共養對象了');
    }

    for (int i = 0; i < 5; i++) {
      final code = _generateCode();
      final ref = _db.collection('invites').doc(code);
      if ((await ref.get()).exists) continue;

      await ref.set({
        'fromUid': uid,
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 2)),
        ),
        'used': false,
        'usedBy': null,
        'usedAt': null,
      });

      return code;
    }

    throw Exception('產生邀請碼失敗');
  }

  /// 兌換邀請碼
  static Future<void> redeemInviteCode(String code) async {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final inviteRef = _db.collection('invites').doc(code);
    final myRef = _db.collection('users').doc(me);

    await _db.runTransaction((tx) async {
      final inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) throw Exception('邀請碼不存在');

      final invite = inviteSnap.data()!;
      if (invite['used'] == true) throw Exception('邀請碼已被使用');

      if (DateTime.now().isAfter((invite['expiresAt'] as Timestamp).toDate())) {
        throw Exception('邀請碼已過期');
      }

      final fromUid = invite['fromUid'];
      if (fromUid == me) throw Exception('不能用自己的邀請碼');

      final mySnap = await tx.get(myRef);
      if (mySnap.data()?['partnerUid'] != null) {
        throw Exception('你已經有兄弟了...');
      }

      final fromRef = _db.collection('users').doc(fromUid);
      final fromSnap = await tx.get(fromRef);
      if (fromSnap.data()?['partnerUid'] != null) {
        throw Exception('對方已經有別的兄弟了');
      }

      tx.update(inviteRef, {
        'used': true,
        'usedBy': me,
        'usedAt': Timestamp.now(),
      });

      tx.set(myRef, {'partnerUid': fromUid}, SetOptions(merge: true));
      tx.set(fromRef, {'partnerUid': me}, SetOptions(merge: true));
    });
  }
}
