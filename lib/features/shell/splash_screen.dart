import 'package:flutter/material.dart';

/// ログイン直後、アカウント種別(role)を取得している間に表示するスプラッシュ。
/// role が確定すると router の redirect が適切なホームへ遷移させる。
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
