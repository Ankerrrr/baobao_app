import 'package:flutter/material.dart';
import '../services/invite_service.dart';
import '../services/auth_service.dart';

class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  String? _code;
  final _controller = TextEditingController();

  @override
  void dispose() {
    AuthService.syncUserProfile();

    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新增兄弟')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () async {
                try {
                  final code = await InviteService.createInviteCode();
                  setState(() => _code = code);
                } catch (e) {
                  _show(e.toString());
                }
              },
              child: const Text('產生邀請碼'),
            ),

            if (_code != null)
              SelectableText(
                '你的邀請碼：$_code',
                style: Theme.of(context).textTheme.headlineSmall,
              ),

            const Divider(height: 32),

            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: '輸入邀請碼'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await InviteService.redeemInviteCode(
                    _controller.text.trim().toUpperCase(),
                  );
                  _show('綁定成功！');
                } catch (e) {
                  _show(e.toString());
                }
              },
              child: const Text('送出邀請碼'),
            ),
          ],
        ),
      ),
    );
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
