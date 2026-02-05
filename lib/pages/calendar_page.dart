import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  Stream<List<_Event>>? _eventStream;
  final Set<String> _eventDays = {};
  final Map<String, String> _nicknameMap = {};

  String get myUid => _auth.currentUser!.uid;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  late Future<String?> _relationshipFuture;
  DateTime? _loadedMonth;

  @override
  void initState() {
    super.initState();
    _relationshipFuture = _getRelationshipId();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNicknames();
    });
  }

  Future<void> _editEvent(String relationshipId, _Event event) async {
    final result = await showDialog<_EventDraft>(
      context: context,
      builder: (_) => _EditEventDialog(event: event, selectedDay: _selectedDay),
    );

    if (result == null) return;

    await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('events')
        .doc(event.id)
        .update({
          'title': result.title,
          'detail': result.detail,
          'time': result.time == null ? null : Timestamp.fromDate(result.time!),
        });

    await _loadMonthEventDays(relationshipId, _focusedDay);
  }

  Future<void> _loadNicknames() async {
    final myDoc = await _db.collection('users').doc(myUid).get();
    final myData = myDoc.data();
    if (myData == null) return;

    final partnerUid = myData['partnerUid'] as String?;
    final myRel = myData['relationship'] as Map<String, dynamic>?;

    // ⭐ 自己：固定顯示「我」
    _nicknameMap[myUid] = '自己';

    // ⭐ 對方：從「我自己的 relationship.nickname」拿
    if (partnerUid != null) {
      final partnerNickname = (myRel?['nickname'] as String?)?.trim();

      _nicknameMap[partnerUid] = partnerNickname?.isNotEmpty == true
          ? partnerNickname!
          : '對方';
    }

    setState(() {});
  }

  Future<String?> _getRelationshipId() async {
    final doc = await _db.collection('users').doc(myUid).get();
    final partnerUid = doc.data()?['partnerUid'];
    if (partnerUid == null) return null;

    final ids = [myUid, partnerUid]..sort();
    return ids.join('_');
  }

  Future<void> _deleteEvent(String relationshipId, _Event event) async {
    await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('events')
        .doc(event.id) // ⭐ 用 id
        .delete();

    // 刪除後更新月曆小點
    await _loadMonthEventDays(relationshipId, _focusedDay);
  }

  Stream<List<_Event>> _eventsStream(String relationshipId, DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);

    return _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('events')
        .where('date', isEqualTo: dateStr)
        // ❌ 不要 orderBy
        .snapshots()
        .map((snap) {
          return snap.docs.map((d) {
            final data = d.data();
            final ts = data['time'] as Timestamp?;

            return _Event(
              id: d.id,
              title: data['title'],
              detail: (data['detail'] ?? '') as String,
              createdBy: data['createdBy'] as String,
              time: ts?.toDate(),
            );
          }).toList();
        });
  }

  Future<void> _addEvent(String relationshipId) async {
    final event = await showDialog<_EventDraft>(
      context: context,
      builder: (_) => _AddEventDialog(selectedDay: _selectedDay),
    );

    if (event == null) return;

    await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('events')
        .add({
          'title': event.title,
          'detail': event.detail,
          'date': DateFormat('yyyy-MM-dd').format(_selectedDay),
          'time': event.time == null
              ? null
              : Timestamp.fromDate(event.time!), // ⭐ 關鍵
          'createdBy': myUid,
          'createdAt': FieldValue.serverTimestamp(),
        });

    await _loadMonthEventDays(relationshipId, _focusedDay);
  }

  Future<void> _loadMonthEventDays(
    String relationshipId,
    DateTime month,
  ) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);

    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);

    final snap = await _db
        .collection('relationships')
        .doc(relationshipId)
        .collection('events')
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThanOrEqualTo: endStr)
        .get();

    _eventDays
      ..clear()
      ..addAll(snap.docs.map((d) => d['date'] as String));

    setState(() {}); // ⭐ 讓月曆重畫
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _relationshipFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final relationshipId = snap.data;
        if (relationshipId == null) {
          return const Center(child: Text('尚未綁定對象'));
        }

        // ⭐ 初始化當日事件 stream
        _eventStream ??= _eventsStream(relationshipId, _selectedDay);

        // ⭐ 載入當月有活動的日期（給月曆小點）
        if (_loadedMonth == null ||
            _loadedMonth!.year != _focusedDay.year ||
            _loadedMonth!.month != _focusedDay.month) {
          _loadedMonth = _focusedDay;
          _loadMonthEventDays(relationshipId, _focusedDay);
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _addEvent(relationshipId),
            child: const Icon(Icons.add),
          ),
          body: Column(
            children: [
              TableCalendar(
                locale: 'zh_TW',
                daysOfWeekHeight: 28, // ⭐ 原本太小，調高
                rowHeight: 58, // ⭐ 日期格高度，避免壓縮
                firstDay: DateTime(2020),
                lastDay: DateTime(2030),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(day, _selectedDay),

                headerStyle: const HeaderStyle(formatButtonVisible: false),

                eventLoader: (day) {
                  final key = DateFormat('yyyy-MM-dd').format(day);
                  return _eventDays.contains(key) ? [1] : [];
                },

                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                    _eventStream = _eventsStream(relationshipId, selected);
                  });
                },

                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                  _loadMonthEventDays(relationshipId, focusedDay);
                },

                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;

                    return Positioned(
                      bottom: 12, // ⭐ 點點高度（你已經在用這個概念）
                      child: Container(
                        width: 4, // ⭐ 點點大小（改這裡）
                        height: 4, // ⭐ 點點大小（改這裡）
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),

                calendarStyle: CalendarStyle(
                  // 📅 平日（乾淨白）
                  defaultTextStyle: const TextStyle(
                    color: Color(0xFFEAEAEA), // 柔白，不死白
                    fontWeight: FontWeight.w500,
                  ),

                  // 🟠 週六 / 週日（溫暖橘粉，不刺眼）
                  weekendTextStyle: const TextStyle(
                    color: Color(0xFFFF9F6E), // 奶橘色
                    fontWeight: FontWeight.w600,
                  ),

                  // 🔵 今天（藍色焦點）
                  todayDecoration: const BoxDecoration(
                    color: Color(0xFF4DA3FF), // 柔藍
                    shape: BoxShape.circle,
                  ),

                  // 🟠 選取日期（橘色呼應週末）
                  selectedDecoration: const BoxDecoration(
                    color: Color(0xFFFF8A3D), // 活潑橘
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              const Divider(),

              Expanded(
                child: StreamBuilder<List<_Event>>(
                  stream: _eventStream,
                  builder: (context, eventSnap) {
                    if (eventSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final List<_Event> events = eventSnap.data ?? <_Event>[];

                    if (events.isEmpty) {
                      return const Center(child: Text('當日沒有活動'));
                    }

                    return ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: events.length,

                      // ⭐ 每筆下面的框線
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        thickness: 0.6,
                        color: Color(0xFF2C2C2C), // 深色柔和線
                      ),

                      itemBuilder: (context, i) {
                        final e = events[i];

                        return Dismissible(
                          key: ValueKey(e.id), // ⭐ 一定要唯一
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: Colors.redAccent,
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (direction) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('刪除活動'),
                                content: const Text('確定要刪除這個活動嗎？'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('刪除'),
                                  ),
                                ],
                              ),
                            );
                          },
                          onDismissed: (direction) {
                            _deleteEvent(relationshipId, e);
                          },

                          child: InkWell(
                            onTap: () => _editEvent(relationshipId, e),
                            child: ListTile(
                              leading: const Icon(Icons.event),
                              title: Text(e.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (e.time != null)
                                    Text(
                                      DateFormat('HH:mm').format(e.time!),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.orangeAccent,
                                      ),
                                    ),
                                  if (e.detail.isNotEmpty)
                                    Text(
                                      e.detail,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '新增人: ${_nicknameMap[e.createdBy] ?? '未知'}',
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
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddEventDialog extends StatefulWidget {
  final DateTime selectedDay; // ⭐ 新增

  const _AddEventDialog({required this.selectedDay});

  @override
  State<_AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<_AddEventDialog> {
  final _titleCtrl = TextEditingController();
  final _detailCtrl = TextEditingController();
  TimeOfDay? _selectedTime;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增活動'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: '活動名稱'),
          ),
          TextField(
            controller: _detailCtrl,
            maxLines: 1,
            decoration: const InputDecoration(
              labelText: '詳細內容',
              hintText: '例如：騎腳踏車',
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.schedule),
            label: Text(
              _selectedTime == null
                  ? '選擇時間（可選）'
                  : _selectedTime!.format(context),
            ),
            onPressed: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (t != null) {
                setState(() => _selectedTime = t);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleCtrl.text.trim().isEmpty) return;

            DateTime? fullTime;
            if (_selectedTime != null) {
              fullTime = DateTime(
                widget.selectedDay.year,
                widget.selectedDay.month,
                widget.selectedDay.day,
                _selectedTime!.hour,
                _selectedTime!.minute,
              );
            }

            Navigator.pop(
              context,
              _EventDraft(
                _titleCtrl.text.trim(),
                _detailCtrl.text.trim(),
                fullTime,
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
    _detailCtrl.dispose();
    super.dispose();
  }
}

class _Event {
  final String id;
  final String title;
  final String detail;
  final String createdBy;
  final DateTime? time;

  _Event({
    required this.id,
    required this.title,
    required this.detail,
    required this.createdBy,
    this.time,
  });
}

class _EventDraft {
  final String title;
  final String detail;
  final DateTime? time;

  _EventDraft(this.title, this.detail, this.time);
}

class _EditEventDialog extends StatefulWidget {
  final _Event event;
  final DateTime selectedDay;

  const _EditEventDialog({required this.event, required this.selectedDay});

  @override
  State<_EditEventDialog> createState() => _EditEventDialogState();
}

class _EditEventDialogState extends State<_EditEventDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _detailCtrl;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.event.title);
    _detailCtrl = TextEditingController(text: widget.event.detail);

    if (widget.event.time != null) {
      _selectedTime = TimeOfDay.fromDateTime(widget.event.time!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('編輯活動'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: '活動名稱'),
          ),
          TextField(
            controller: _detailCtrl,
            maxLines: 1,
            decoration: const InputDecoration(
              labelText: '詳細內容',
              hintText: '例如：騎腳踏車',
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(
                  _selectedTime == null
                      ? '設定時間'
                      : _selectedTime!.format(context),
                ),
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime ?? TimeOfDay.now(),
                  );
                  if (t != null) {
                    setState(() => _selectedTime = t);
                  }
                },
              ),
              if (_selectedTime != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: '清除時間',
                  onPressed: () => setState(() => _selectedTime = null),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleCtrl.text.trim().isEmpty) return;

            DateTime? fullTime;
            if (_selectedTime != null) {
              fullTime = DateTime(
                widget.selectedDay.year,
                widget.selectedDay.month,
                widget.selectedDay.day,
                _selectedTime!.hour,
                _selectedTime!.minute,
              );
            }

            Navigator.pop(
              context,
              _EventDraft(
                _titleCtrl.text.trim(),
                _detailCtrl.text.trim(),
                fullTime,
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
    _detailCtrl.dispose();
    super.dispose();
  }
}
