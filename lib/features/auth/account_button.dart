import 'package:flutter/material.dart';

import '../../core/supabase.dart';

/// AppBar に置くアカウントメニュー。
/// 現在のユーザー（メール）表示とログアウトを提供する。
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '未ログイン';
    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle),
      onSelected: (value) async {
        if (value == 'signout') {
          await supabase.auth.signOut();
          // ログアウト後の遷移は router の redirect が担当する
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(email, style: Theme.of(context).textTheme.bodySmall),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signout',
          child: Text('ログアウト'),
        ),
      ],
    );
  }
}
