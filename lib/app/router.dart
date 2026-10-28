import 'package:go_router/go_router.dart';

import '../core/auth_controller.dart';
import '../features/auth/auth_screen.dart';
import '../features/coupons/coupons_screen.dart';
import '../features/dictionary/dictionary_detail_screen.dart';
import '../features/dictionary/dictionary_list_screen.dart';
import '../features/map/map_screen.dart';
import '../features/owner/group_form_screen.dart';
import '../features/owner/group_management_screen.dart';
import '../features/owner/menu_management_screen.dart';
import '../features/owner/owner_home_screen.dart';
import '../features/owner/restaurant_form_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/shell/splash_screen.dart';

/// 飲食店オーナー専用エリアのパス接頭辞。
const _ownerAreaPrefix = '/owner';

/// アプリのルーティング定義。
/// - 未ログインなら /login へリダイレクト
/// - ログイン直後は role 取得まで /splash
/// - 一般ユーザー: マップ / 辞典 / クーポン（店舗エリアは不可）
/// - 飲食店オーナー: 店舗（ユーザー向けタブは不可）
final appRouter = GoRouter(
  initialLocation: '/map',
  refreshListenable: authController,
  redirect: (context, state) {
    final loc = state.matchedLocation;

    // 1) 未ログイン → ログイン画面のみ許可
    if (!authController.isLoggedIn) {
      return loc == '/login' ? null : '/login';
    }

    // 2) ログイン済みだが role 取得中 → スプラッシュで待機
    if (authController.roleLoading) {
      return loc == '/splash' ? null : '/splash';
    }

    // 3) role 確定後。ログイン/スプラッシュに留まらせず、種別のホームへ
    final isOwner = authController.isOwner;
    final home = isOwner ? '/owner' : '/map';
    if (loc == '/login' || loc == '/splash') return home;

    // 4) アカウント種別ごとのアクセス制御
    final inOwnerArea = loc.startsWith(_ownerAreaPrefix);
    if (isOwner && !inOwnerArea) return '/owner'; // オーナーはユーザー向け画面に入らせない
    if (!isOwner && inOwnerArea) return '/map'; // 一般ユーザーは店舗エリアに入らせない

    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    // 辞典詳細はマップ・一覧どちらからも開く共通ルート（全画面表示）
    GoRoute(
      path: '/restaurant/:id',
      builder: (context, state) => DictionaryDetailScreen(
        restaurantId: state.pathParameters['id']!,
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/map',
              builder: (context, state) => const MapScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dictionaries',
              builder: (context, state) => const DictionaryListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/coupons',
              builder: (context, state) => const CouponsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/owner',
              builder: (context, state) => const OwnerHomeScreen(),
              routes: [
                GoRoute(
                  path: 'restaurant',
                  builder: (context, state) => const RestaurantFormScreen(),
                ),
                GoRoute(
                  path: 'menus',
                  builder: (context, state) => const MenuManagementScreen(),
                ),
                GoRoute(
                  path: 'groups',
                  builder: (context, state) => const GroupManagementScreen(),
                  routes: [
                    GoRoute(
                      path: 'new',
                      builder: (context, state) => const GroupFormScreen(),
                    ),
                    // 既存グループ（＋クーポン）の編集
                    GoRoute(
                      path: ':id/edit',
                      builder: (context, state) => GroupFormScreen(
                        groupId: state.pathParameters['id'],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
