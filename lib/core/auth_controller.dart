import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

/// 認証状態と、ログイン中ユーザーの「アカウント種別(role)」を保持する。
///
/// role は profiles テーブルから取得する:
///   - 'user'  … 一般ユーザー（学生）→ マップ / 辞典 / クーポン
///   - 'owner' … 飲食店オーナー       → 店舗
///   - 'admin' … 管理者（今回は owner と同等に扱わない。将来拡張用）
///
/// ChangeNotifier なので go_router の refreshListenable に渡せば、
/// ログイン・ログアウト・role 取得完了のたびに redirect が再評価される。
class AuthController extends ChangeNotifier {
  AuthController() {
    // 永続化されたセッションがあれば、初回 redirect が即ログイン状態を見られるよう同期取得
    _session = supabase.auth.currentSession;
    // 認証状態の変化（初回セッション・ログイン・ログアウト等）を購読
    _sub = supabase.auth.onAuthStateChange.listen(_onAuthChange);
    if (_session != null) {
      // 既存セッションぶんの role を取得（非同期）
      _loadRole();
    }
  }

  late final StreamSubscription<AuthState> _sub;

  Session? _session;
  String? _role; // null = 未取得

  /// ログイン済みか
  bool get isLoggedIn => _session != null;

  /// 取得済みの role（未取得なら null）
  String? get role => _role;

  /// ログイン済みだが role をまだ取得できていない（ローディング中）
  bool get roleLoading => isLoggedIn && _role == null;

  /// 飲食店オーナーアカウントか
  bool get isOwner => _role == 'owner';

  Future<void> _onAuthChange(AuthState state) async {
    final prevUserId = _session?.user.id;
    _session = state.session;

    if (_session == null) {
      // ログアウト
      _role = null;
      notifyListeners();
      return;
    }

    // ユーザーが変わった / まだ role 未取得なら取得する
    if (_session!.user.id != prevUserId || _role == null) {
      _role = null;
      notifyListeners(); // ローディング状態を即反映（redirect がスプラッシュへ）
      await _loadRole();
    } else {
      notifyListeners();
    }
  }

  Future<void> _loadRole() async {
    final userId = _session?.user.id;
    if (userId == null) return;
    try {
      final data = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      // プロフィール未作成などで取れない場合は一般ユーザー扱い
      _role = (data?['role'] as String?) ?? 'user';
    } catch (_) {
      // 取得失敗時も一般ユーザーとして進ませる（タブが出ないより安全側）
      _role = 'user';
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// アプリ全体で共有する認証コントローラ。
final authController = AuthController();
