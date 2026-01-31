import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/interactive_baby.dart';

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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('寶寶84'),

        // ⭐ 左上角：Google 頭貼 + 選單
        leading: PopupMenuButton<String>(
          tooltip: '帳號選單',
          onSelected: (value) async {
            if (value == 'logout') {
              await FirebaseAuth.instance.signOut();
            }
          },
          itemBuilder: (context) => [
            // 使用者資訊（不可點）
            PopupMenuItem<String>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user?.displayName ?? '使用者'),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

            const PopupMenuDivider(),

            // 登出（可點）
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

          // ⭐ 顯示頭貼
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: user?.photoURL != null
                  ? NetworkImage(user!.photoURL!)
                  : null,
              child: user?.photoURL == null ? const Icon(Icons.person) : null,
            ),
          ),
        ),
      ),

      body: _pages[_index],

      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.child_care), label: '寶寶'),
          NavigationDestination(icon: Icon(Icons.photo), label: '照片'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: '分帳'),
        ],
      ),
    );
  }
}
