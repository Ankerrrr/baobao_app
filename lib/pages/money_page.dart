import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key});

  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends State<MoneyPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _dateFmt = DateFormat('yyyy-MM-dd');

  String get myUid => _auth.currentUser!.uid;

  String? _partnerUid;
  String _partnerName = '兄弟';
  _BillListFilter _filter = _BillListFilter.unsettled;

  late Future<String?> _relationshipFuture; // ⭐ 關鍵

  @override
  void initState() {
    super.initState();
    _relationshipFuture = _initRelationship(); // ⭐ 只跑一次
  }

  /// ✅ 初始化關係（可以 setState）
  Future<String?> _initRelationship() async {
    final myDoc = await _db.collection('users').doc(myUid).get();
    final myData = myDoc.data();
    if (myData == null) return null;

    final partnerUid = myData['partnerUid'] as String?;
    if (partnerUid == null || partnerUid.isEmpty) return null;

    _partnerUid = partnerUid;

    final nickname =
        (myData?['relationship']?['nickname'] as String?)?.trim().isNotEmpty ==
            true
        ? myData!['relationship']['nickname']
        : '兄弟';

    setState(() {
      _partnerName = nickname;
    });

    final ids = [myUid, partnerUid]..sort();
    return ids.join('_');
  }

  Future<void> _editBill(String relationshipId, _Bill bill) async {
    final result = await showDialog<_Bill>(
      context: context,
      builder: (_) =>
          _EditBillDialog(bill: bill, partnerName: _partnerName, myUid: myUid),
    );

    if (result == null) return;

    final payerUid =
        result.payerUid == myUid ? myUid : (_partnerUid ?? myUid);
    final date = result.date ?? _dateFmt.format(DateTime.now());

    await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('bills')
        .doc(bill.id)
        .update({
      'title': result.title,
      'amount': result.amount,
      'payerUid': payerUid,
      'myShare': result.myShare,
      'shareUid': myUid,
      'date': date,

      // ⭐ 關鍵
      'editedBy': myUid,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  String _formatTime(Timestamp? t) {
    if (t == null) return '';
    final d = t.toDate();
    return '${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// bills stream
  Stream<List<_Bill>> _billsStream(String relationshipId) {
    return _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('bills')
        .orderBy('editedAt', descending: true)
        .snapshots()
        .map((snap) {
          final bills = snap.docs.map((d) {
            final data = d.data();
            String? date = data['date'] as String?;
            final editedAt = data['editedAt'] as Timestamp?;
            date ??= editedAt == null ? null : _dateFmt.format(editedAt.toDate());
            final rawMyShare = (data['myShare'] as num).toDouble();
            final shareUid =
                (data['shareUid'] as String?) ?? (data['editedBy'] as String?);
            final myShareForMe = (shareUid == null || shareUid == myUid)
                ? rawMyShare
                : (1 - rawMyShare);
            return _Bill(
              id: d.id,
              title: data['title'],
              amount: (data['amount'] as num).toDouble(),
              payerUid: data['payerUid'],
              myShare: myShareForMe,
              rawMyShare: rawMyShare,
              shareUid: shareUid,
              editedBy: data['editedBy'] as String,
              settled: data['settled'] ?? false,
              editedAt: data['editedAt'],
              date: date,
            );
          }).toList();

          return bills;
        });
  }

  DateTime? _effectiveDate(_Bill b) {
    if (b.date != null) {
      try {
        return DateTime.parse(b.date!);
      } catch (_) {}
    }
    return b.editedAt?.toDate();
  }

  Future<void> _pickFilter() async {
    final picked = await showModalBottomSheet<_BillListFilter>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.list),
                title: const Text('全部'),
                onTap: () => Navigator.pop(context, _BillListFilter.all),
              ),
              ListTile(
                leading: const Icon(Icons.pending_actions),
                title: const Text('未完成'),
                onTap: () => Navigator.pop(context, _BillListFilter.unsettled),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('已完成'),
                onTap: () => Navigator.pop(context, _BillListFilter.settled),
              ),
            ],
          ),
        );
      },
    );

    if (picked == null) return;
    setState(() => _filter = picked);
  }

  Future<void> _markAllSettled(String relationshipId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部完成'),
        content: const Text('確定要把所有未完成分帳標記為已完成嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確定'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final query = await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('bills')
        .where('settled', isEqualTo: false)
        .get();

    final docs = query.docs;
    if (docs.isEmpty) return;

    // Firestore batch 上限 500
    for (var i = 0; i < docs.length; i += 450) {
      final batch = _db.batch();
      final chunk = docs.skip(i).take(450);
      for (final d in chunk) {
        batch.update(d.reference, {
          'settled': true,
          'editedBy': myUid,
          'editedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  Future<void> _addBill(String relationshipId) async {
    final bill = await showDialog<_Bill>(
      context: context,
      builder: (_) => _AddBillDialog(),
    );

    if (bill == null || _partnerUid == null) return;

    final payerUid = bill.payerUid == myUid ? myUid : _partnerUid!; // ⭐ 正確替換
    final date = bill.date ?? _dateFmt.format(DateTime.now());

    await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('bills')
        .add({
      'title': bill.title,
      'amount': bill.amount,
      'payerUid': payerUid,
      'myShare': bill.myShare,
      'shareUid': myUid,
      'date': date,

      // ⭐ 核心
      'editedBy': myUid,
      'editedAt': FieldValue.serverTimestamp(),
      'settled': false,
    });
  }

  double _calcBalance(List<_Bill> bills) {
    double balance = 0;

    for (final b in bills) {
      if (b.settled) continue;

      if (b.payerUid == myUid) {
        // 我付錢 → 對方欠我
        balance += b.amount * (1 - b.myShare);
      } else {
        // 對方付錢 → 我欠對方
        balance -= b.amount * b.myShare;
      }
    }

    return balance;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _relationshipFuture, // ⭐ 不會再無限跑
      builder: (context, relSnap) {
        if (relSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final relationshipId = relSnap.data;
        if (relationshipId == null) {
          return const Scaffold(body: Center(child: Text('尚未綁定對象')));
        }

        return StreamBuilder<List<_Bill>>(
          stream: _billsStream(relationshipId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final bills = snap.data!;
            final filteredBills = bills.where((b) {
              switch (_filter) {
                case _BillListFilter.all:
                  return true;
                case _BillListFilter.unsettled:
                  return !b.settled;
                case _BillListFilter.settled:
                  return b.settled;
              }
            }).toList();

            filteredBills.sort((a, b) {
              final da = _effectiveDate(a);
              final db = _effectiveDate(b);
              if (da != null && db != null) {
                final c = db.compareTo(da); // 新到舊
                if (c != 0) return c;
              } else if (da == null && db != null) {
                return 1;
              } else if (da != null && db == null) {
                return -1;
              }

              final ea = a.editedAt?.toDate();
              final eb = b.editedAt?.toDate();
              if (ea != null && eb != null) return eb.compareTo(ea);
              if (ea == null && eb != null) return 1;
              if (ea != null && eb == null) return -1;
              return 0;
            });

            final balance = _calcBalance(bills);
            final total = bills
                .where((b) => !b.settled)
                .fold<double>(0, (s, b) => s + b.amount);

            return Scaffold(
              appBar: AppBar(
                title: const Text('分帳'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.filter_alt),
                    tooltip: '篩選',
                    onPressed: _pickFilter,
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () => _addBill(relationshipId),
                child: const Icon(Icons.add),
              ),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _markAllSettled(relationshipId),
                        icon: const Icon(Icons.done_all),
                        label: const Text('全部完成'),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildSettlementText(balance),
                  ),
                  Text('總金額 \$${total.toStringAsFixed(0)}'),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredBills.length,
                      itemBuilder: (context, i) {
                        final b = filteredBills[i];
                        final payerName = b.payerUid == myUid
                            ? '自己'
                            : _partnerName;

                        return Dismissible(
                          key: ValueKey(b.id),
                          direction: DismissDirection.horizontal,
                          dismissThresholds: const {
                            DismissDirection.startToEnd: 0.6,
                            DismissDirection.endToStart: 0.6,
                          },
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            color: Colors.green,
                            child: const Icon(Icons.check, color: Colors.white),
                          ),

                          secondaryBackground: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),

                          confirmDismiss: (direction) async {
                            final ref = _db
                                .collection('relationships')
                                .doc(relationshipId)
                                .collection('bills')
                                .doc(b.id);

                            if (direction == DismissDirection.endToStart) {
                              // 左滑刪除
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('刪除分帳'),
                                  content: Text(
                                    b.editedBy == myUid
                                        ? '確定要刪除這筆分帳？'
                                        : '這是 $_partnerName 編輯的，確定要刪除？',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('刪除'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await ref.delete();
                              }

                              return false; // ⭐ 不讓Dismissible真的刪掉UI
                            }

                            // 右滑 → 完成/恢復
                            await ref.update({
                              'settled': !b.settled,
                              'editedAt': FieldValue.serverTimestamp(),
                            });

                            return false; // ⭐ 重要
                          },

                          child: InkWell(
                            onTap: () => _editBill(relationshipId, b),
                            child: Opacity(
                              opacity: b.settled ? 0.35 : 1,
                              child: ListTile(
                                title: Builder(
                                  builder: (context) {
                                    final d = _effectiveDate(b);
                                    if (d == null) return Text(b.title);
                                    return Text('${d.month}/${d.day} ${b.title}');
                                  },
                                ),
                                subtitle: Text(
                                  b.myShare == 0.5
                                      ? '付款人：$payerName'
                                      : '付款人：$payerName｜付 ${(b.myShare * 100).round()}%',
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('\$${b.amount.toStringAsFixed(0)}'),
                                    Text(
                                      '編輯者: ${b.editedBy == myUid ? '自己' : _partnerName}  ${_formatTime(b.editedAt)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettlementText(double b) {
    if (b.abs() < 0.01) return const Text('已結清!!');

    return Text(
      b > 0
          ? '$_partnerName 要給我 \$${b.toStringAsFixed(0)}'
          : '我要給 $_partnerName \$${(-b).toStringAsFixed(0)}',
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
  }
}

enum _BillListFilter {
  all,
  unsettled,
  settled,
}

class _Bill {
  final String id;
  final String title;
  final double amount;
  final String payerUid;
  final double myShare;
  final double rawMyShare; // stored in Firestore
  final String? shareUid; // whose "myShare" the raw value refers to
  final String editedBy;
  final bool settled;
  final Timestamp? editedAt;
  final String? date; // yyyy-MM-dd

  _Bill({
    required this.id,
    required this.title,
    required this.amount,
    required this.payerUid,
    required this.myShare,
    required this.rawMyShare,
    required this.shareUid,
    required this.editedBy,
    required this.settled,
    this.editedAt,
    this.date,
  });
}

class _AddBillDialog extends StatefulWidget {
  @override
  State<_AddBillDialog> createState() => _AddBillDialogState();
}

class _AddBillDialogState extends State<_AddBillDialog> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  bool _custom = false;
  double _myShare = 0.5;
  String _payer = '我'; // 我 / 對方
  DateTime _date = DateTime.now();
  final _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增分帳'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('日期'),
              subtitle: Text(_dateFmt.format(_date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  setState(() => _date = picked);
                }
              },
            ),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: '項目'),
            ),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '金額'),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _payer,
              decoration: const InputDecoration(labelText: '付款人'),
              items: const [
                DropdownMenuItem(value: '我', child: Text('我')),
                DropdownMenuItem(value: '對方', child: Text('對方')),
              ],
              onChanged: (v) => setState(() => _payer = v!),
            ),

            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('自訂比例'),
              value: _custom,
              onChanged: (v) => setState(() => _custom = v),
            ),

            if (_custom) ...[
              Slider(
                value: _myShare,
                min: 0,
                max: 1,
                divisions: 20,
                label: '${(_myShare * 100).round()}%',
                onChanged: (v) => setState(() => _myShare = v),
              ),
              Text('我負擔 ${(_myShare * 100).round()}%'),
            ] else
              const Text('比例：50 / 50'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            final amount = double.tryParse(_amountCtrl.text) ?? 0;

            if (title.isEmpty || amount <= 0) return;

            Navigator.pop(
              context,
              _Bill(
                id: '',
                title: title,
                amount: amount,
                payerUid: _payer == '我'
                    ? FirebaseAuth.instance.currentUser!.uid
                    : 'PARTNER',
                myShare: _custom ? _myShare : 0.5,
                rawMyShare: _custom ? _myShare : 0.5,
                shareUid: FirebaseAuth.instance.currentUser!.uid,
                editedBy: FirebaseAuth.instance.currentUser!.uid,
                settled: false, // ⭐ 新增
                date: _dateFmt.format(_date),
              ),
            );
          },
          child: const Text('新增'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }
}

class _EditBillDialog extends StatefulWidget {
  final _Bill bill;
  final String partnerName;
  final String myUid;

  const _EditBillDialog({
    required this.bill,
    required this.partnerName,
    required this.myUid,
  });

  @override
  State<_EditBillDialog> createState() => _EditBillDialogState();
}

class _EditBillDialogState extends State<_EditBillDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _amountCtrl;

  late bool _custom;
  late double _myShare;
  late String _payer; // 我 / 對方
  late DateTime _date;
  final _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.bill.title);
    _amountCtrl = TextEditingController(
      text: widget.bill.amount.toStringAsFixed(0),
    );

    _myShare = widget.bill.myShare;
    _custom = widget.bill.myShare != 0.5;

    _payer = widget.bill.payerUid == widget.myUid ? '我' : '對方';
    _date = widget.bill.date == null
        ? DateTime.now()
        : DateTime.parse(widget.bill.date!);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('編輯分帳'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('日期'),
              subtitle: Text(_dateFmt.format(_date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  setState(() => _date = picked);
                }
              },
            ),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: '項目'),
            ),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '金額'),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _payer,
              decoration: const InputDecoration(labelText: '付款人'),
              items: const [
                DropdownMenuItem(value: '我', child: Text('我')),
                DropdownMenuItem(value: '對方', child: Text('對方')),
              ],
              onChanged: (v) => setState(() => _payer = v!),
            ),

            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('自訂比例'),
              value: _custom,
              onChanged: (v) => setState(() => _custom = v),
            ),

            if (_custom) ...[
              Slider(
                value: _myShare,
                min: 0,
                max: 1,
                divisions: 20,
                label: '${(_myShare * 100).round()}%',
                onChanged: (v) => setState(() => _myShare = v),
              ),
              Text('我負擔 ${(_myShare * 100).round()}%'),
            ] else
              const Text('比例：50 / 50'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            final amount = double.tryParse(_amountCtrl.text) ?? 0;

            if (title.isEmpty || amount <= 0) return;

            Navigator.pop(
              context,
              _Bill(
                id: widget.bill.id,
                title: title,
                amount: amount,
                payerUid: _payer == '我' ? widget.myUid : 'PARTNER',
                myShare: _custom ? _myShare : 0.5,
                rawMyShare: _custom ? _myShare : 0.5,
                shareUid: widget.myUid,
                editedBy: widget.myUid,
                settled: widget.bill.settled, // ⭐ 保留原狀態
                date: _dateFmt.format(_date),
              ),
            );
          },
          child: const Text('儲存'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }
}
