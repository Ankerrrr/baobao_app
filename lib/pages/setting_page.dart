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
  bool _loading = true;

  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadDate();
  }

  Future<void> _loadDate() async {
    final snap = await _db.collection('users').doc(_uid).get();
    final ts = snap.data()?['relationship']?['startDate'];

    setState(() {
      _startDate = ts is Timestamp ? ts.toDate() : null;
      _loading = false;
    });
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

    await _db.collection('users').doc(_uid).set({
      'relationship': {'startDate': Timestamp.fromDate(picked)},
    }, SetOptions(merge: true));

    setState(() {
      _startDate = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _startDate == null
        ? '尚未設定'
        : DateFormat('yyyy/MM/dd').format(_startDate!);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 12),

                /// ❤️ 交往日期
                ListTile(
                  leading: const Icon(Icons.favorite),
                  title: const Text('做兄弟日期'),
                  subtitle: Text(dateText),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDate,
                ),
              ],
            ),
    );
  }
}
