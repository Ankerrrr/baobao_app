import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      // Web/Android 通用：用 google_sign_in 拿到 Google 帳號
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // 使用者取消

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final res = await FirebaseAuth.instance.signInWithCredential(credential);
      debugPrint('✅ Google 登入成功 uid=${res.user?.uid}');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google 登入成功：${res.user?.email ?? ''}')),
        );
      }
    } catch (e) {
      debugPrint('❌ Google 登入失敗: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Google 登入失敗：$e')));
      }
    }
  }

  Future<void> _signInAnonymously(BuildContext context) async {
    try {
      final res = await FirebaseAuth.instance.signInAnonymously();
      debugPrint('✅ 匿名登入成功 uid=${res.user?.uid}');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('匿名登入成功')));
      }
    } catch (e) {
      debugPrint('❌ 匿名登入失敗: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('匿名登入失敗：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('寶寶84', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 18),

              // ✅ Google 登入
              SizedBox(
                width: 260,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('使用 Google 登入'),
                  onPressed: () => _signInWithGoogle(context),
                ),
              ),

              const SizedBox(height: 12),

              // ✅ 匿名登入（保留測試）
              SizedBox(
                width: 260,
                height: 48,
                child: OutlinedButton(
                  child: const Text('匿名登入（測試）'),
                  onPressed: () => _signInAnonymously(context),
                ),
              ),

              const SizedBox(height: 12),
              Text('登入後會自動進入首頁', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
