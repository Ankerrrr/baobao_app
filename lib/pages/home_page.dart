import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../widgets/interactive_baby.dart';
import 'invite_page.dart';
import 'setting_page.dart';
import 'message_page.dart';
import 'money_page.dart';
import 'calendar_page.dart';
import '../services/auth_service.dart';
import 'package:google_fonts/google_fonts.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  final _pages = const [InteractiveBaby(), CalendarPage(), MoneyPage()];

  bool _synced = false;

  static const List<Map<String, String>> animalOptions = [
    {'id': 'cat', 'label': '貓咪', 'emoji': '🐱'},
    {'id': 'dog', 'label': '狗狗', 'emoji': '🐶'},
    {'id': 'rabbit', 'label': '兔子', 'emoji': '🐰'},
    {'id': 'bear', 'label': '小熊', 'emoji': '🐻'},
    {'id': 'fox', 'label': '狐狸', 'emoji': '🦊'},
    {'id': 'tiger', 'label': '老虎', 'emoji': '🐯'},
    {'id': 'panda', 'label': '熊貓', 'emoji': '🐼'},
    {'id': 'hamster', 'label': '倉鼠', 'emoji': '🐹'},
    {'id': 'duck', 'label': '小鴨', 'emoji': '🦆'},
    {'id': 'dinosaur', 'label': '恐龍', 'emoji': '🦖'},
    {'id': 'mermaid', 'label': '美人魚', 'emoji': '🧜'},
    {'id': 'santa', 'label': '聖誕老人', 'emoji': '🧑‍🎄'},
  ];

  @override
  void initState() {
    super.initState();

    // ⭐ HomePage 第一次出現時同步使用者資料
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_synced) return;
      _synced = true;
      await AuthService.syncUserProfile();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _myDocStream(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  String _getAnimalEmoji(String? animalId) {
    if (animalId == null) return '';

    final match = animalOptions.firstWhere(
      (a) => a['id'] == animalId,
      orElse: () => {},
    );

    return match['emoji'] ?? '';
  }

  void _showDetailsSheet(
    BuildContext context, {
    required User authUser,
    required String? partnerUid,
    required DateTime? startDate,
    required String myNickname,
    required String? relationshipId,
    required String? myAnimalId,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題
                Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Text('詳細資訊', style: Theme.of(ctx).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),

                // ⭐ 自己（如果有 partnerUid，就從「對方 uid」讀 relationship.nickname，表示對方幫我取的名字）
                if (partnerUid == null)
                  ListTile(
                    leading: _AvatarWithAnimal(
                      photoUrl: authUser.photoURL,
                      emoji: _getAnimalEmoji(myAnimalId),
                    ),

                    title: Text(authUser.displayName ?? '我'),
                    subtitle: Text(authUser.email ?? ''),
                  )
                else
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(partnerUid)
                        .snapshots(),
                    builder: (context, snap) {
                      final pData = snap.data?.data();

                      // 對方幫我取的暱稱：存在「對方 uid doc」的 relationship.nickname
                      final partnerRel = pData?['relationship'];
                      final myNickFromPartner = (partnerRel is Map)
                          ? (partnerRel['nickname'] as String?)?.trim() ?? ''
                          : '';

                      final myDisplayName = (authUser.displayName ?? '').trim();

                      final myEmoji = _getAnimalEmoji(myAnimalId);

                      final myTitle = myNickFromPartner.isNotEmpty
                          ? (myDisplayName.isNotEmpty
                                ? '$myNickFromPartner（$myDisplayName）'
                                : myNickFromPartner)
                          : (myDisplayName.isNotEmpty ? myDisplayName : '我');

                      return ListTile(
                        leading: _AvatarWithAnimal(
                          photoUrl: authUser.photoURL,
                          emoji: _getAnimalEmoji(myAnimalId),
                        ),
                        title: Text(myTitle),
                        subtitle: Text(authUser.email ?? ''),
                      );
                    },
                  ),

                // ⭐ 對方（顯示：我幫對方取的暱稱，存在「自己的 uid doc」→ 由 myNickname 傳進來）
                if (partnerUid != null)
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(partnerUid)
                        .snapshots(),
                    builder: (context, snap) {
                      final p = snap.data?.data();

                      final displayName =
                          (p?['displayName'] as String?)?.trim() ?? '';
                      final pEmail = (p?['email'] as String?) ?? '';
                      final pPhoto = (p?['photoURL'] as String?) ?? '';

                      final partnerAnimalId =
                          p?['relationship']?['animal'] as String?;
                      final partnerEmoji = _getAnimalEmoji(partnerAnimalId);
                      final pTitle = myNickname.isNotEmpty
                          ? (displayName.isNotEmpty
                                ? '$myNickname（$displayName）'
                                : myNickname)
                          : (displayName.isNotEmpty ? displayName : '未命名');

                      return ListTile(
                        leading: _AvatarWithAnimal(
                          photoUrl: pPhoto,
                          emoji: partnerEmoji,
                        ),

                        title: Text(pTitle),
                        subtitle: Text(pEmail),
                      );
                    },
                  ),

                // 交往日期與天數
                ListTile(
                  leading: const Icon(Icons.favorite, color: Colors.pink),
                  title: startDate == null
                      ? const Text('尚未設定')
                      : Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: '當了 '),
                              TextSpan(
                                text:
                                    '${DateTime.now().difference(startDate!).inDays} 天',
                                style: const TextStyle(
                                  color: Color.fromARGB(255, 249, 19, 157),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const TextSpan(text: ' 的兄弟'),
                            ],
                          ),
                          style: Theme.of(ctx).textTheme.bodyMedium, // ⭐ 關鍵
                        ),
                ),

                const SizedBox(height: 8),
                const Divider(),
                if (relationshipId != null)
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('relationships')
                        .doc(relationshipId)
                        .snapshots(),
                    builder: (context, snap) {
                      final data = snap.data?.data();
                      final earned =
                          data?['foodEarnedBy'] as Map<String, dynamic>? ?? {};

                      final myFood = earned[authUser.uid] as int? ?? 0;
                      final partnerFood = partnerUid != null
                          ? (earned[partnerUid] as int? ?? 0)
                          : 0;

                      return ListTile(
                        leading: const Icon(
                          Icons.restaurant,
                          color: Colors.orange,
                        ),
                        title: const Text('飼料貢獻'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('你：$myFood 顆'),
                            if (partnerUid != null) Text('對方：$partnerFood 顆'),
                          ],
                        ),
                      );
                    },
                  ),

                // // 快捷鍵：去設定頁
                // SizedBox(
                //   width: double.infinity,
                //   child: ElevatedButton.icon(
                //     icon: const Icon(Icons.settings),
                //     label: const Text('前往設定'),
                //     onPressed: () {
                //       Navigator.pop(ctx); // 先關 sheet
                //       Navigator.push(
                //         context,
                //         MaterialPageRoute(builder: (_) => const SettingPage()),
                //       );
                //     },
                //   ),
                // ),
              ],
            ),
          ),
        );
      },
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _todaySpecialStream() {
    final now = DateTime.now();

    return FirebaseFirestore.instance
        .collection('special_days')
        .where('month', isEqualTo: now.month)
        .where('day', isEqualTo: now.day)
        .where('isEnabled', isEqualTo: true)
        .snapshots();
  }

  void _showFestivalDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return const Scaffold(body: Center(child: Text('未登入')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _myDocStream(authUser.uid),
      builder: (context, mySnap) {
        // 讀取我的 Firestore user doc
        final myData = mySnap.data?.data();
        final partnerUid = myData?['partnerUid'] as String?;
        final myNickname =
            (myData?['relationship']?['nickname'] as String?)?.trim() ?? '';

        final Timestamp? startTs = myData?['relationship']?['startDate'];
        final DateTime? startDate = startTs?.toDate();

        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(100),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ⭐ 原本 AppBar（全部包進來）
                AppBar(
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('寶寶84'),

                      const SizedBox(width: 8),

                      // ⭐ 節日膠囊
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _todaySpecialStream(),
                        builder: (context, snap) {
                          if (!snap.hasData || snap.data!.docs.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final doc = snap.data!.docs.first;
                          final title = doc['title'] ?? '';
                          final content = doc['content'] ?? '';

                          return GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                barrierDismissible: true,
                                builder: (_) => _RingBoxDialog(
                                  title: title,
                                  content: content,
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // 🔴 紅色背景 + 白色圓點
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _DotPainter(),
                                        ),
                                      ),

                                      // ⭐ 前景文字
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),

                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [_SeesawText(text: title)],
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
                    ],
                  ),
                  surfaceTintColor: const Color.fromARGB(255, 0, 0, 0),

                  leading: PopupMenuButton<String>(
                    tooltip: '選單',
                    icon: const Icon(Icons.arrow_drop_down_outlined),
                    onSelected: (value) async {
                      if (value == 'logout') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('登出'),
                            content: const Text('確定要登出嗎？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('登出'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await FirebaseAuth.instance.signOut();
                          await GoogleSignIn().disconnect(); // ⭐ 強制下次選帳號
                        }
                      }

                      if (value == 'invite') {
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const InvitePage()),
                        );
                      }

                      if (value == 'settings') {
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingPage(),
                          ),
                        );
                      }

                      if (value == 'messages') {
                        if (!mounted || partnerUid == null) return;

                        final rid = ([
                          authUser.uid,
                          partnerUid,
                        ]..sort()).join('_');

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HeroControllerScope.none(
                              child: MessagePage(
                                key: messagePageStateKey, // ⭐⭐⭐
                                relationshipId: rid,
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      // 自己資訊（不可點）
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(authUser.displayName ?? '使用者'),
                            const SizedBox(height: 6),
                            Text(
                              authUser.email ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),

                      // 只有未綁定才顯示新增好友
                      if (partnerUid == null)
                        const PopupMenuItem<String>(
                          value: 'invite',
                          child: Row(
                            children: [
                              Icon(Icons.person_add, size: 18),
                              SizedBox(width: 8),
                              Text('新增兄弟'),
                            ],
                          ),
                        ),

                      const PopupMenuItem<String>(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.tune, size: 18),
                            SizedBox(width: 8),
                            Text('設定'),
                          ],
                        ),
                      ),

                      const PopupMenuItem<String>(
                        value: 'messages',
                        child: Row(
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 18),
                            SizedBox(width: 8),
                            Text('訊息'),
                          ],
                        ),
                      ),

                      const PopupMenuItem<String>(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 18),
                            SizedBox(width: 8),
                            Text('登出'),
                          ],
                        ),
                      ),
                    ],
                  ),

                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          _showDetailsSheet(
                            context,
                            authUser: authUser,
                            partnerUid: partnerUid,
                            startDate: startDate,
                            myNickname: myNickname,
                            relationshipId: partnerUid == null
                                ? null
                                : ([
                                    authUser.uid,
                                    partnerUid,
                                  ]..sort()).join('_'),
                            myAnimalId:
                                myData?['relationship']?['animal'] as String?,
                          );
                        },
                        child: partnerUid == null
                            ? CircleAvatar(
                                radius: 16,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                backgroundImage: authUser.photoURL != null
                                    ? NetworkImage(authUser.photoURL!)
                                    : null,
                                child: authUser.photoURL == null
                                    ? const Icon(Icons.person, size: 16)
                                    : null,
                              )
                            : StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: _userDocStream(partnerUid),
                                builder: (context, pSnap) {
                                  final p = pSnap.data?.data();
                                  final partnerPhotoURL =
                                      (p?['photoURL'] as String?) ?? '';

                                  return _CoupleAvatar(
                                    myPhotoURL: authUser.photoURL,
                                    partnerPhotoURL: partnerPhotoURL,
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          body: IndexedStack(index: _index, children: _pages),

          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.child_care), label: '寶寶'),
              NavigationDestination(
                icon: Icon(Icons.calendar_month),
                label: '日曆',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long),
                label: '分帳',
              ),
            ],
          ),
        );
      },
    );
  }
}

// /// AppBar 下方的小狀態列：顯示已綁定的人
// class _PartnerBar extends StatelessWidget {
//   final String? partnerUid;
//   final Stream<DocumentSnapshot<Map<String, dynamic>>>? partnerStream;
//   final DateTime? startDate;

//   const _PartnerBar({
//     required this.partnerUid,
//     required this.partnerStream,
//     required this.startDate,
//   });

//   // @override
//   // Widget build(BuildContext context) {
//   //   // 尚未綁定
//   //   if (partnerUid == null) {
//   //     return Container(
//   //       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
//   //       decoration: BoxDecoration(
//   //         borderRadius: BorderRadius.circular(14),
//   //         color: Theme.of(context).colorScheme.surfaceContainerHighest,
//   //       ),
//   //       child: Row(
//   //         children: [
//   //           const Icon(Icons.link_off, size: 18),
//   //           const SizedBox(width: 8),
//   //           Text('尚未綁定任何兄弟對象', style: Theme.of(context).textTheme.bodyMedium),
//   //         ],
//   //       ),
//   //     );
//   //   }

//   //   // 已綁定：讀對方資料
//   //   // return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
//   //   //   stream: partnerStream,
//   //   //   builder: (context, snap) {
//   //   //     final partner = snap.data?.data();
//   //   //     final name =
//   //   //         ((partner?['displayName'] as String?)?.trim().isNotEmpty ?? false)
//   //   //         ? partner!['displayName']
//   //   //         : '未命名';
//   //   //     final email = (partner?['email'] as String?) ?? '';
//   //   //     final photoURL = (partner?['photoURL'] as String?) ?? '';

//   //   //     return Container(
//   //   //       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
//   //   //       decoration: BoxDecoration(
//   //   //         borderRadius: BorderRadius.circular(14),
//   //   //         color: Theme.of(context).colorScheme.surfaceContainerHighest,
//   //   //       ),
//   //   //       child: Row(
//   //   //         children: [
//   //   //           CircleAvatar(
//   //   //             radius: 16,
//   //   //             backgroundImage: photoURL.isNotEmpty
//   //   //                 ? NetworkImage(photoURL)
//   //   //                 : null,
//   //   //             child: photoURL.isEmpty
//   //   //                 ? const Icon(Icons.person, size: 16)
//   //   //                 : null,
//   //   //           ),
//   //   //           const SizedBox(width: 20),
//   //   //           Expanded(
//   //   //             child: Column(
//   //   //               crossAxisAlignment: CrossAxisAlignment.start,
//   //   //               mainAxisSize: MainAxisSize.min,
//   //   //               children: [
//   //   //                 Row(
//   //   //                   children: [
//   //   //                     // 👤 名字
//   //   //                     Expanded(
//   //   //                       child: Text(
//   //   //                         '你的兄弟：$name',
//   //   //                         style: Theme.of(context).textTheme.bodyMedium,
//   //   //                         overflow: TextOverflow.ellipsis,
//   //   //                       ),
//   //   //                     ),

//   //   //                     // ⏱ 天數（靠右）
//   //   //                     if (startDate != null)
//   //   //                       Text(
//   //   //                         '${DateTime.now().difference(startDate!).inDays} 天',
//   //   //                         style: Theme.of(context).textTheme.bodySmall,
//   //   //                       ),
//   //   //                   ],
//   //   //                 ),
//   //   //               ],
//   //   //             ),
//   //   //           ),

//   //   //           Text('❤️', style: Theme.of(context).textTheme.bodyMedium),
//   //   //         ],
//   //   //       ),
//   //   //     );
//   //   //   },
//   //   // );
//   // }
// }

class _CoupleAvatar extends StatelessWidget {
  final String? myPhotoURL;
  final String partnerPhotoURL;

  const _CoupleAvatar({
    required this.myPhotoURL,
    required this.partnerPhotoURL,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 對方（後面）
          Positioned(
            left: 0,
            top: 0,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: CircleAvatar(
                radius: 14,
                backgroundImage: partnerPhotoURL.isNotEmpty
                    ? NetworkImage(partnerPhotoURL)
                    : null,
                child: partnerPhotoURL.isEmpty
                    ? const Icon(Icons.person, size: 14)
                    : null,
              ),
            ),
          ),
          // 自己（前面）
          Positioned(
            left: 18, // 疊多少：小一點更重疊
            top: 0,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: CircleAvatar(
                radius: 14,
                backgroundImage: (myPhotoURL != null && myPhotoURL!.isNotEmpty)
                    ? NetworkImage(myPhotoURL!)
                    : null,
                child: (myPhotoURL == null || myPhotoURL!.isEmpty)
                    ? const Icon(Icons.person, size: 14)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarWithAnimal extends StatelessWidget {
  final String? photoUrl;
  final String emoji;

  const _AvatarWithAnimal({required this.photoUrl, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 👤 原本頭貼
          CircleAvatar(
            radius: 22,
            backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
                ? NetworkImage(photoUrl!)
                : null,
            child: (photoUrl == null || photoUrl!.isEmpty)
                ? const Icon(Icons.person)
                : null,
          ),

          // 🐱 左上角動物
          if (emoji.isNotEmpty)
            Positioned(
              top: -0,
              left: -12,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(blurRadius: 4, color: Colors.black12),
                  ],
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 14)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 🔴 紅色底
    final bgPaint = Paint()..color = const Color(0xFFD32F2F); // 好看的紅

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(999),
    );

    canvas.drawRRect(rect, bgPaint);

    // ⚪ 白色小圓點
    final dotPaint = Paint()..color = const Color.fromARGB(62, 255, 255, 255);

    const dotRadius = 0.8; // 更小
    const spacing = 8.0;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x + 4, y + 4), dotRadius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RingBoxDialog extends StatefulWidget {
  final String title;
  final String content;

  const _RingBoxDialog({required this.title, required this.content});

  @override
  State<_RingBoxDialog> createState() => _RingBoxDialogState();
}

class _RingBoxDialogState extends State<_RingBoxDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _openAnim;
  late Animation<double> _textAnim;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _openAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

    _textAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  final double boxHeight = 380;
  final double boxMarginBottom = 60;
  final double lidHeight = 200;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        height: boxHeight + boxMarginBottom + 80, // ⭐ 重點
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none, // ⭐ 允許超出
              children: [
                // 📦 盒子底
                Container(
                  width: 240,
                  height: boxHeight,
                  margin: EdgeInsets.only(bottom: boxMarginBottom),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B0000),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Container(
                      width: 230,
                      height: 350,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1B2F), // 深藍絨布
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),

                      child: FadeTransition(
                        opacity: _textAnim,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,

                            children: [
                              Text(
                                textAlign: TextAlign.center,
                                softWrap: true,
                                "❤️",
                                style: TextStyle(fontSize: 40),
                              ),
                              Text(
                                widget.title,
                                textAlign: TextAlign.center,

                                style: GoogleFonts.notoSerifTc(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.pinkAccent,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.content,
                                textAlign: TextAlign.left,
                                style: GoogleFonts.notoSerifTc(
                                  fontSize: 18,
                                  height: 1.5,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 🟥 蓋子
                Positioned(
                  bottom: boxMarginBottom + boxHeight - 200,
                  child: Transform(
                    alignment: Alignment.topCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.004)
                      ..rotateX(-_openAnim.value * 2),
                    child: ClipPath(
                      clipper: _LidClipper(_openAnim.value),
                      child: Container(
                        width: 240,
                        height: lidHeight,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFB71C1C), Color(0xFF8B0000)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),

                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(18),
                          ),
                        ),
                        child: CustomPaint(painter: _HeartPatternPainter()),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LidClipper extends CustomClipper<Path> {
  final double progress;

  _LidClipper(this.progress);

  @override
  Path getClip(Size size) {
    final shrink = size.width * 0.25 * progress;
    // 0.15 控制收多少

    return Path()
      ..moveTo(0, 0) // 上左（轉軸不動）
      ..lineTo(size.width, 0) // 上右（轉軸不動）
      ..lineTo(size.width - shrink, size.height) // 右下往內收
      ..lineTo(shrink, size.height) // 左下往內收
      ..close();
  }

  @override
  bool shouldReclip(covariant _LidClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _HeartPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(139, 235, 114, 114)
      ..style = PaintingStyle.fill;

    const spacing = 40.0;
    const heartSize = 8.0;

    for (double x = 20; x < size.width; x += spacing) {
      for (double y = 20; y < size.height; y += spacing) {
        _drawHeart(canvas, Offset(x, y), heartSize, paint);
      }
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy + size / 2);

    path.cubicTo(
      center.dx - size,
      center.dy - size / 3,
      center.dx - size * 1.2,
      center.dy + size / 2,
      center.dx,
      center.dy + size,
    );

    path.cubicTo(
      center.dx + size * 1.2,
      center.dy + size / 2,
      center.dx + size,
      center.dy - size / 3,
      center.dx,
      center.dy + size / 2,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SeesawText extends StatefulWidget {
  final String text;

  const _SeesawText({required this.text});

  @override
  State<_SeesawText> createState() => _SeesawTextState();
}

class _SeesawTextState extends State<_SeesawText>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _angle;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _angle = Tween<double>(
      begin: -0.02, // 左傾
      end: 0.02, // 右傾
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _angle,
      builder: (context, child) {
        return Transform.rotate(
          angle: _angle.value,
          alignment: Alignment.center,
          child: child,
        );
      },
      child: Text(
        widget.text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
