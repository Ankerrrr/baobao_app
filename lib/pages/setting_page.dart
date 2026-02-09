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

  bool _countdownEnabled = false;
  Map<String, dynamic>? _countdownEvent;
  bool _countdownNotifyEnabled = false;

  String? _relationshipId;

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

  Future<void> _saveCountdown({
    required bool enabled,
    Map<String, dynamic>? event,
  }) async {
    if (_relationshipId == null) return;

    // 1. 建立基礎資料，確保通知開關一定會被更新
    final Map<String, dynamic> countdown = {
      'enabled': enabled,
      'notifyEnabled': _countdownNotifyEnabled, // 直接讀取目前的 state
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (enabled && event != null) {
      // 2. 選好活動時，合併活動資訊
      countdown['eventId'] = event['eventId'];
      countdown['eventTitle'] = event['eventTitle'];
      countdown['targetAt'] = event['targetAt'];
    } else if (!enabled) {
      // 3. 關閉倒數時，移除活動欄位
      countdown.addAll({
        'eventId': FieldValue.delete(),
        'eventTitle': FieldValue.delete(),
        'targetAt': FieldValue.delete(),
      });
    }

    await _db.collection('relationships').doc(_relationshipId).set({
      'countdown': countdown,
    }, SetOptions(merge: true));
  }

  Future<void> _loadRelationship() async {
    final snap = await _db.collection('users').doc(_uid).get();
    final data = snap.data();

    final rel = data?['relationship'];
    final ts = (rel is Map) ? rel['startDate'] : null;
    final nick = (rel is Map) ? (rel['nickname'] as String?) : null;

    // ⭐ 取得 relationshipId
    final partnerUid = data?['partnerUid'] as String?;
    if (partnerUid != null) {
      final ids = [_uid, partnerUid]..sort();
      _relationshipId = ids.join('_');

      // ⭐ 讀 countdown
      final relDoc = await _db
          .collection('relationships')
          .doc(_relationshipId)
          .get();

      final cd = relDoc.data()?['countdown'];
      if (cd is Map) {
        _countdownEnabled = cd['enabled'] == true;
        _countdownNotifyEnabled = cd['notifyEnabled'] == true;
        _countdownEvent = Map<String, dynamic>.from(cd);
      }
    }

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

  Future<void> _pickCountdownEvent() async {
    if (_relationshipId == null) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('relationships')
              .doc(_relationshipId)
              .collection('events')
              .orderBy('date')
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs;

            if (docs.isEmpty) {
              return SizedBox(
                width: double.infinity, // ⭐ 關鍵：撐滿
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.event_busy, size: 40, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('尚無任何日曆活動', textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }

            final now = DateTime.now();

            return ListView(
              children: docs.map((d) {
                final e = d.data();

                final String dateStr = e['date']; // yyyy-MM-dd
                final DateTime baseDate = DateTime.parse(dateStr);

                DateTime targetAt;

                if (e['time'] != null) {
                  final t = (e['time'] as Timestamp).toDate();
                  targetAt = DateTime(
                    baseDate.year,
                    baseDate.month,
                    baseDate.day,
                    t.hour,
                    t.minute,
                  );
                } else {
                  // 沒時間 → 00:00
                  targetAt = DateTime(
                    baseDate.year,
                    baseDate.month,
                    baseDate.day,
                    0,
                    0,
                  );
                }

                // ❌ 已過期 → 不顯示
                if (targetAt.isBefore(now)) {
                  return const SizedBox.shrink();
                }

                // ✅ 未來活動
                return ListTile(
                  title: Text(e['title'] ?? ''),
                  subtitle: Text(
                    DateFormat('yyyy/MM/dd HH:mm').format(targetAt),
                  ),
                  onTap: () {
                    Navigator.pop(context, {
                      'eventId': d.id,
                      'eventTitle': e['title'],
                      'targetAt': Timestamp.fromDate(targetAt),
                    });
                  },
                );
              }).toList(),
            );
          },
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _countdownEvent = picked;
    });

    await _saveCountdown(enabled: true, event: picked);
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

                // 🏷️ 對方暱稱
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

                const Divider(),

                // ⏱️ 倒數計時器標題
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '倒數計時器(同時會調整對方的裝置)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),

                // ⏱️ 啟用倒數
                SwitchListTile(
                  secondary: const Icon(Icons.timer_outlined),
                  title: const Text('啟用倒數計時'),
                  value: _countdownEnabled,
                  onChanged: (v) async {
                    setState(() {
                      _countdownEnabled = v;
                      _countdownEvent = null; // UI 先清
                    });

                    await _saveCountdown(
                      enabled: v,
                      event: null, // ⭐ 強制刪掉舊 event
                    );
                  },
                ),

                // 📅 選擇活動
                if (_countdownEnabled)
                  ListTile(
                    leading: const Icon(Icons.event),
                    title: Text(
                      _countdownEvent == null
                          ? '選擇日曆活動'
                          : _countdownEvent!['eventTitle'] ?? '未命名活動',
                    ),
                    subtitle: _countdownEvent == null
                        ? null
                        : (() {
                            final ta = _countdownEvent!['targetAt'];
                            if (ta is! Timestamp) return null;

                            return Text(
                              DateFormat(
                                'yyyy/MM/dd HH:mm',
                              ).format(ta.toDate()),
                            );
                          })(),

                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickCountdownEvent,
                  ),
                if (_countdownEnabled)
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('倒數提醒通知'),
                    subtitle: const Text('忍者點兄弟\n啟用後每天早上將發送通知'),
                    value: _countdownNotifyEnabled,
                    onChanged: (v) async {
                      setState(() {
                        _countdownNotifyEnabled = v;
                      });

                      // ⭐ 只更新通知狀態，不動 event
                      await _saveCountdown(
                        enabled: true,
                        event: _countdownEvent,
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
