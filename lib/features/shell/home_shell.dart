import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_controller.dart';

/// 下部ナビゲーションのシェル。
/// アカウント種別(role)に応じて表示タブを切り替える:
///   - 一般ユーザー: マップ / 辞典 / クーポン
///   - 飲食店オーナー: 店舗
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    // StatefulShellRoute のブランチ順に対応:
    //   branch 0=マップ / 1=辞典 / 2=クーポン / 3=店舗
    const userDestinations = [
      _ShellDestination(
        branch: 0,
        icon: Icon(Icons.map_outlined),
        selectedIcon: Icon(Icons.map),
        label: 'マップ',
      ),
      _ShellDestination(
        branch: 1,
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: '辞典',
      ),
      _ShellDestination(
        branch: 2,
        icon: Icon(Icons.local_offer_outlined),
        selectedIcon: Icon(Icons.local_offer),
        label: 'クーポン',
      ),
    ];
    const ownerDestinations = [
      _ShellDestination(
        branch: 3,
        icon: Icon(Icons.storefront_outlined),
        selectedIcon: Icon(Icons.storefront),
        label: '店舗',
      ),
    ];

    final destinations =
        authController.isOwner ? ownerDestinations : userDestinations;

    // NavigationBar は2項目以上が必須。オーナーはタブが1つ（店舗）だけなので
    // 下部ナビを出さず、店舗管理画面を全面表示する（遷移は画面内のリストから）。
    if (destinations.length < 2) {
      return Scaffold(body: navigationShell);
    }

    // 現在のブランチに対応する表示上のインデックス（見つからなければ先頭）
    var selectedIndex =
        destinations.indexWhere((d) => d.branch == navigationShell.currentIndex);
    if (selectedIndex < 0) selectedIndex = 0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          final branch = destinations[index].branch;
          navigationShell.goBranch(
            branch,
            // 同じタブを再タップしたら、そのタブの初期画面に戻す
            initialLocation: branch == navigationShell.currentIndex,
          );
        },
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// 下部ナビ 1 項目と、対応する StatefulShellRoute のブランチ番号。
class _ShellDestination {
  const _ShellDestination({
    required this.branch,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final int branch;
  final Widget icon;
  final Widget selectedIcon;
  final String label;
}
