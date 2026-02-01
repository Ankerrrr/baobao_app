import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  DateTime? _startDate;
  String _nickname = '';
  bool _loading = true;
  bool _saving = false;

  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseFirestore.instance;

  final _nicknameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRelationship();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRelationship() async {
    final snap = await _db.collection('users').doc(_uid).get();
    final data = snap.data();

    final rel = data?['relationship'];
    final ts = (rel is Map) ? rel['startDate'] : null;
    final nick = (rel is Map) ? (rel['nickname'] as String?) : null;

    setState(() {
      _startDate = ts is Timestamp ? ts.toDate() : null;
      _nickname = (nick ?? '').trim();
      _nicknameCtrl.text = _nickname;
      _loading = false;
    });
  }

  Future<void> _saveRelationship({
    DateTime? startDate,
    String? nickname,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);

    final myRef = _db.collection('users').doc(_uid);

    // 讀 partnerUid（只有 startDate 需要用到）
    final mySnap = await myRef.get();
    final myData = mySnap.data();
    final partnerUid = myData?['partnerUid'] as String?;

    final batch = _db.batch();

    // 同步（自己 + 對方）
    if (startDate != null) {
      final datePayload = {
        'relationship': {
          'startDate': Timestamp.fromDate(startDate),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      };

      batch.set(myRef, datePayload, SetOptions(merge: true));

      if (partnerUid != null && partnerUid.isNotEmpty) {
        final partnerRef = _db.collection('users').doc(partnerUid);
        batch.set(partnerRef, datePayload, SetOptions(merge: true));
      }
    }

    // 只更新自己
    if (nickname != null) {
      final nickPayload = {
        'relationship': {
          'nickname': nickname,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      };
      batch.set(myRef, nickPayload, SetOptions(merge: true));
    }

    await batch.commit();
    if (!mounted) return;
    setState(() => _saving = false);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );

    if (picked == null) return;

    await _saveRelationship(startDate: picked);

    setState(() {
      _startDate = picked;
    });
  }

  Future<void> _editNickname() async {
    _nicknameCtrl.text = _nickname;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('⚠️對方可見'),
          content: TextField(
            controller: _nicknameCtrl,
            decoration: const InputDecoration(hintText: '例如:薰薰寶寶'),
            maxLength: 20,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final nick = _nicknameCtrl.text.trim();

    await _saveRelationship(nickname: nick);

    setState(() {
      _nickname = nick;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _startDate == null
        ? '尚未設定'
        : DateFormat('yyyy/MM/dd').format(_startDate!);

    final nicknameText = _nickname.isEmpty ? '尚未設定' : _nickname;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 12),

                // ❤️ 做兄弟日期
                ListTile(
                  leading: const Icon(Icons.favorite),
                  title: const Text('第一天'),
                  subtitle: Text(dateText),
                  trailing: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _saving ? null : _pickDate,
                ),

                // 🏷️ 對方暱稱（存在 relationship.nickname）
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('對方暱稱'),
                  subtitle: Text(nicknameText),
                  trailing: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _saving ? null : _editNickname,
                ),
              ],
            ),
    );
  }
}
