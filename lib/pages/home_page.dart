import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/interactive_baby.dart';
import 'invite_page.dart';
import 'setting_page.dart';
import '../services/auth_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  final _pages = const [
    InteractiveBaby(),
    Center(child: Text('照片')),
    Center(child: Text('分帳')),
  ];

  bool _synced = false; // ⭐ 確保只同步一次

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

  Stream<DocumentSnapshot<Map<String, dynamic>>> _myDocStream(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  void _showDetailsSheet(
    BuildContext context, {
    required User authUser,
    required String? partnerUid,
    required DateTime? startDate,
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

                // 自己
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: authUser.photoURL != null
                        ? NetworkImage(authUser.photoURL!)
                        : null,
                    child: authUser.photoURL == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(authUser.displayName ?? '我'),
                  subtitle: Text(authUser.email ?? ''),
                ),

                // 對方（有 partnerUid 才顯示）
                if (partnerUid != null)
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(partnerUid)
                        .snapshots(),
                    builder: (context, snap) {
                      final p = snap.data?.data();
                      final pName =
                          ((p?['displayName'] as String?)?.trim().isNotEmpty ??
                              false)
                          ? (p!['displayName'] as String)
                          : '未命名';
                      final pEmail = (p?['email'] as String?) ?? '';
                      final pPhoto = (p?['photoURL'] as String?) ?? '';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: pPhoto.isNotEmpty
                              ? NetworkImage(pPhoto)
                              : null,
                          child: pPhoto.isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(pName),
                        subtitle: Text(pEmail),
                      );
                    },
                  ),

                const Divider(),

                // 交往日期與天數
                ListTile(
                  leading: const Icon(Icons.favorite),
                  title: const Text('做兄弟日期'),
                  subtitle: Text(
                    startDate == null
                        ? '尚未設定'
                        : '${startDate.year}/${startDate.month.toString().padLeft(2, '0')}/${startDate.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: startDate == null
                      ? null
                      : Text(
                          '總共當了 ${DateTime.now().difference(startDate).inDays} 天的兄弟',
                        ),
                ),

                const SizedBox(height: 8),

                // 快捷鍵：去設定頁
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: const Text('前往設定'),
                    onPressed: () {
                      Navigator.pop(ctx); // 先關 sheet
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingPage()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      // 理論上不會來到這，保險
      return const Scaffold(body: Center(child: Text('未登入')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _myDocStream(authUser.uid),
      builder: (context, mySnap) {
        // 讀取我的 Firestore user doc
        final myData = mySnap.data?.data();
        final partnerUid = myData?['partnerUid'] as String?;

        final Timestamp? startTs = myData?['relationship']?['startDate'];
        final DateTime? startDate = startTs?.toDate();

        return Scaffold(
          appBar: AppBar(
            title: const Text('寶寶84'),

            // ✅ 左邊改成設定 icon + PopupMenu
            leading: PopupMenuButton<String>(
              tooltip: '選單',
              icon: const Icon(Icons.settings),
              onSelected: (value) async {
                if (value == 'logout') {
                  await FirebaseAuth.instance.signOut();
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
                    MaterialPageRoute(builder: (_) => const SettingPage()),
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
                        Text('新增好友'),
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

            // ✅ 右邊改成兩人頭貼：點了開詳細資訊
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
                      : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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

          body: _pages[_index],

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

/// AppBar 下方的小狀態列：顯示已綁定的人
class _PartnerBar extends StatelessWidget {
  final String? partnerUid;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? partnerStream;
  final DateTime? startDate;

  const _PartnerBar({
    required this.partnerUid,
    required this.partnerStream,
    required this.startDate,
  });

  @override
  Widget build(BuildContext context) {
    // 尚未綁定
    if (partnerUid == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            const Icon(Icons.link_off, size: 18),
            const SizedBox(width: 8),
            Text('尚未綁定任何兄弟對象', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    // 已綁定：讀對方資料
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: partnerStream,
      builder: (context, snap) {
        final partner = snap.data?.data();
        final name =
            ((partner?['displayName'] as String?)?.trim().isNotEmpty ?? false)
            ? partner!['displayName']
            : '未命名';
        final email = (partner?['email'] as String?) ?? '';
        final photoURL = (partner?['photoURL'] as String?) ?? '';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: photoURL.isNotEmpty
                    ? NetworkImage(photoURL)
                    : null,
                child: photoURL.isEmpty
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // 👤 名字
                        Expanded(
                          child: Text(
                            '你的兄弟：$name',
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // ⏱ 天數（靠右）
                        if (startDate != null)
                          Text(
                            '${DateTime.now().difference(startDate!).inDays} 天',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              Text('❤️', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        );
      },
    );
  }
}

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
