import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/interactive_baby.dart';
import 'invite_page.dart';
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

        return Scaffold(
          appBar: AppBar(
            title: const Text('寶寶84'),

            // 左上角：自己的頭貼 + 帳號選單
            leading: PopupMenuButton<String>(
              tooltip: '帳號選單',
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
              },
              itemBuilder: (context) => [
                // 自己資訊（不可點）
                PopupMenuItem<String>(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(authUser.displayName ?? '使用者'),
                      const SizedBox(height: 2),
                      Text(
                        authUser.email ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),

                const PopupMenuDivider(),

                // ✅ 只有「尚未綁定」才顯示新增好友
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

              // 顯示自己的頭貼
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  backgroundImage: authUser.photoURL != null
                      ? NetworkImage(authUser.photoURL!)
                      : null,
                  child: authUser.photoURL == null
                      ? const Icon(Icons.person)
                      : null,
                ),
              ),
            ),

            // ✅ AppBar 下方顯示「共養狀態列」
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _PartnerBar(
                  partnerUid: partnerUid,
                  partnerStream: partnerUid == null
                      ? null
                      : _userDocStream(partnerUid),
                ),
              ),
            ),
          ),

          body: _pages[_index],

          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.child_care), label: '寶寶'),
              NavigationDestination(icon: Icon(Icons.photo), label: '照片'),
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

  const _PartnerBar({required this.partnerUid, required this.partnerStream});

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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '你的兄弟❤️：$name',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.link, size: 18),
            ],
          ),
        );
      },
    );
  }
}
