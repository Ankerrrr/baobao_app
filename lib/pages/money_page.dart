import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key});

  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends State<MoneyPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String get myUid => _auth.currentUser!.uid;

  String? _partnerUid;
  String _partnerName = '兄弟';

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

    await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('bills')
        .doc(bill.id)
        .update({
          'title': result.title,
          'amount': result.amount,
          'payerUid': result.payerUid == myUid ? myUid : _partnerUid,
          'myShare': result.myShare,

          // ⭐ 關鍵
          'editedBy': myUid,
          'editedAt': FieldValue.serverTimestamp(),
        });
  }

  /// bills stream
  Stream<List<_Bill>> _billsStream(String relationshipId) {
    return _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('bills')
        .orderBy('editedAt', descending: false)
        .snapshots()
        .map((snap) {
          return snap.docs.map((d) {
            final data = d.data();
            return _Bill(
              id: d.id,
              title: data['title'],
              amount: (data['amount'] as num).toDouble(),
              payerUid: data['payerUid'],
              myShare: (data['myShare'] as num).toDouble(),
              editedBy: data['editedBy'] as String,
            );
          }).toList();
        });
  }

  Future<void> _addBill(String relationshipId) async {
    final bill = await showDialog<_Bill>(
      context: context,
      builder: (_) => _AddBillDialog(),
    );

    if (bill == null || _partnerUid == null) return;

    final payerUid = bill.payerUid == myUid ? myUid : _partnerUid!; // ⭐ 正確替換

    await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('bills')
        .add({
          'title': bill.title,
          'amount': bill.amount,
          'payerUid': payerUid,
          'myShare': bill.myShare,

          // ⭐ 核心
          'editedBy': myUid,
          'editedAt': FieldValue.serverTimestamp(),
        });
  }

  double _calcBalance(List<_Bill> bills) {
    double myPaid = 0;
    double myShouldPay = 0;

    for (final b in bills) {
      if (b.payerUid == myUid) myPaid += b.amount;
      myShouldPay += b.amount * b.myShare;
    }
    return myPaid - myShouldPay;
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
            final balance = _calcBalance(bills);
            final total = bills.fold<double>(0, (s, b) => s + b.amount);

            return Scaffold(
              floatingActionButton: FloatingActionButton(
                onPressed: () => _addBill(relationshipId),
                child: const Icon(Icons.add),
              ),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildSettlementText(balance),
                  ),
                  Text('總金額 \$${total.toStringAsFixed(0)}'),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: bills.length,
                      itemBuilder: (context, i) {
                        final b = bills[i];
                        final payerName = b.payerUid == myUid
                            ? '自己'
                            : _partnerName;

                        return Dismissible(
                          key: ValueKey(b.id),
                          direction: DismissDirection.endToStart, // 只允許左滑
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),

                          confirmDismiss: (_) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('刪除分帳'),
                                content: Text(
                                  b.editedBy == myUid
                                      ? '確定要刪除這筆分帳？'
                                      : '這是 $_partnerName 編輯的，確定要刪除？',

                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
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
                          },

                          onDismissed: (_) async {
                            await _db
                                .collection('relationships')
                                .doc(relationshipId)
                                .collection('bills')
                                .doc(b.id)
                                .delete();
                          },

                          child: InkWell(
                            onTap: () => _editBill(relationshipId, b),
                            child: ListTile(
                              title: Text(b.title),
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
                                    '編輯者: ${b.editedBy == myUid ? '自己' : _partnerName}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
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

class _Bill {
  final String id;
  final String title;
  final double amount;
  final String payerUid;
  final double myShare;
  final String editedBy; // ⭐ 新增

  _Bill({
    required this.id,
    required this.title,
    required this.amount,
    required this.payerUid,
    required this.myShare,
    required this.editedBy,
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增分帳'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                    : 'PARTNER', // ⭐ 會在寫入時被替換
                myShare: _custom ? _myShare : 0.5,
                editedBy: FirebaseAuth.instance.currentUser!.uid,
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
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('編輯分帳'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                payerUid: _payer == '我' ? widget.myUid : 'PARTNER', // 之後會替換
                myShare: _custom ? _myShare : 0.5,
                editedBy: widget.myUid,
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
