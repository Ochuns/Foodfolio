import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../features/auth/auth_screen.dart';
import '../features/coupons/coupons_screen.dart';
import '../features/dictionary/dictionary_detail_screen.dart';
import '../features/dictionary/dictionary_list_screen.dart';
import '../features/map/map_screen.dart';
import '../features/shell/home_shell.dart';

/// アプリのルーティング定義。
/// - 未ログインなら /login へリダイレクト
/// - ログイン済みは下部ナビ（マップ / 辞典 / クーポン）
final appRouter = GoRouter(
  initialLocation: '/map',
  refreshListenable: _AuthNotifier(),
  redirect: (context, state) {
    final loggedIn = supabase.auth.currentSession != null;
    final goingToLogin = state.matchedLocation == '/login';

    if (!loggedIn && !goingToLogin) return '/login';
    if (loggedIn && goingToLogin) return '/map';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const AuthScreen(),
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
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => DictionaryDetailScreen(
                    restaurantId: state.pathParameters['id']!,
                  ),
                ),
              ],
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
      ],
    ),
  ],
);

/// Supabase の認証状態の変化を go_router に通知し、redirect を再評価させる。
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    _sub = supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
