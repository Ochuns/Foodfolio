import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';

/// ログイン / サインアップ画面。
/// メール＋パスワードのシンプル認証（ローカルはメール確認無効なので即ログイン）。
/// 和紙の地に鶴ヶ城を配した会津テーマ。
/// 鶴ヶ城は完成イメージから切り抜いた画像（assets/images/login_*.png）。
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  String? _error;
  // 新規登録時のアカウント種別: 'user' = 一般ユーザー / 'owner' = 飲食店
  String _role = 'user';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await supabase.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          // raw_user_meta_data に入り、handle_new_user トリガーが
          // profiles.display_name / role に反映される
          data: {
            'display_name': _displayName.text.trim(),
            'role': _role,
          },
        );
      }
      // 成功後の画面遷移は router の redirect（認証状態監視）が担当する
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: _AizuColors.inputBorder),
    );
    // フォーム部品を墨茶・金で統一する
    final formTheme = base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _AizuColors.ink,
        primary: _AizuColors.ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _AizuColors.inputFill,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: _AizuColors.gold, width: 1.6),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _AizuColors.linkRed),
      ),
    );

    return Scaffold(
      backgroundColor: _AizuColors.paper,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _WashiPainter())),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Header(),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin ? 'ログイン' : '新規登録',
                        textAlign: TextAlign.center,
                        style: base.textTheme.titleMedium
                            ?.copyWith(color: _AizuColors.ink),
                      ),
                      const SizedBox(height: 20),
                      Theme(data: formTheme, child: _buildFormCard(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 金の二重枠（角が内側にえぐれた額縁）に入ったフォーム。
  Widget _buildFormCard(BuildContext context) {
    return CustomPaint(
      painter: const _GoldFramePainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isLogin) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'アカウント種別',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: _AizuColors.ink),
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'user',
                      label: Text('一般ユーザー'),
                      icon: Icon(Icons.person_outline),
                    ),
                    ButtonSegment(
                      value: 'owner',
                      label: Text('飲食店'),
                      icon: Icon(Icons.storefront_outlined),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged:
                      _loading ? null : (s) => setState(() => _role = s.first),
                ),
                const SizedBox(height: 4),
                Text(
                  _role == 'owner'
                      ? '店舗・メニュー（辞典）・クーポンを管理します。'
                      : 'マップで店を探し、辞典を集めてクーポンを獲得します。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: _AizuColors.ink),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _displayName,
                  decoration: const InputDecoration(labelText: '表示名'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '表示名を入力してください'
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'メールアドレス'),
                validator: (v) => (v == null || !v.contains('@'))
                    ? '正しいメールアドレスを入力してください'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'パスワード（6文字以上）'),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'パスワードは6文字以上です' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              _CastleButton(
                label: _isLogin ? 'ログイン' : '登録する',
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _isLogin = !_isLogin;
                          _error = null;
                        }),
                child: Text(_isLogin
                    ? 'アカウントがない方はこちら（新規登録）'
                    : 'すでにアカウントをお持ちの方（ログイン）'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 画面の配色（和紙・墨茶・金）。
class _AizuColors {
  // 切り抜き画像の地色（247,239,219）に合わせた和紙色
  static const paper = Color(0xFFF7EFDB);
  static const paperLight = Color(0xFFF9F3E3);
  static const paperDark = Color(0xFFEDE2C8);
  static const ink = Color(0xFF3E2C20); // 墨茶（文字・枠）
  // ボタンの地色。お城マーク画像の透過計算に使った色と同じにする
  static const buttonBrown = Color(0xFF483224);
  static const gold = Color(0xFFC9A24A);
  static const goldLight = Color(0xFFE6CD86);
  static const linkRed = Color(0xFF8B2E1F);
  static const inputFill = Color(0xFFFFF9F6);
  static const inputBorder = Color(0xFFCFC6BA);
}

// ---------------------------------------------------------------------------
// ヘッダー（線画の鶴ヶ城・タイトル・奥の鶴ヶ城と霞の画像）
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  // ヘッダー画像（login_header.png）の大きさ。カツ丼の位置はこの座標で指定する
  static const double _designWidth = 614;

  @override
  Widget build(BuildContext context) {
    // 背景画像（筆の払い・タイトル・奥の鶴ヶ城と霞。地色は透過済み）の上に、
    // 元の城があった場所へソースカツ丼の画像を重ねる。
    return LayoutBuilder(
      builder: (context, constraints) {
        final k = constraints.maxWidth / _designWidth;
        return Stack(
          children: [
            Image.asset(
              'assets/images/login_header.png',
              fit: BoxFit.fitWidth,
              filterQuality: FilterQuality.medium,
            ),
            // 丼の底が筆の払いの上端（中央 y=154）に乗るように置く
            Positioned(
              left: 219 * k,
              top: 8 * k,
              width: 172 * k,
              child: Image.asset(
                'assets/images/login_katsudon.png',
                filterQuality: FilterQuality.medium,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 和紙の地（中央が明るいグラデーション＋繊維）。
class _WashiPainter extends CustomPainter {
  const _WashiPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.0,
          colors: [_AizuColors.paperLight, _AizuColors.paper, _AizuColors.paperDark],
          stops: [0.0, 0.7, 1.0],
        ).createShader(rect),
    );

    // 繊維（毎回同じ模様になるよう乱数の種を固定）
    final rand = math.Random(7);
    final fibers = Path();
    final count = (size.width * size.height / 2500).clamp(0, 1200).toInt();
    for (var i = 0; i < count; i++) {
      final x = rand.nextDouble() * size.width;
      final y = rand.nextDouble() * size.height;
      final len = 4 + rand.nextDouble() * 14;
      final a = rand.nextDouble() * math.pi;
      fibers
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + math.cos(a) * len / 2 + rand.nextDouble() * 3,
          y + math.sin(a) * len / 2 + rand.nextDouble() * 3,
          x + math.cos(a) * len,
          y + math.sin(a) * len,
        );
    }
    canvas.drawPath(
      fibers,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = const Color(0x14806040),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// フォーム部品（金の額縁・お城マーク付きボタン）
// ---------------------------------------------------------------------------

/// 角が内側にえぐれた金の二重枠。
class _GoldFramePainter extends CustomPainter {
  const _GoldFramePainter();

  Path _notched(Rect r, double n) {
    final c = Radius.circular(n);
    return Path()
      ..moveTo(r.left + n, r.top)
      ..lineTo(r.right - n, r.top)
      ..arcToPoint(Offset(r.right, r.top + n), radius: c, clockwise: false)
      ..lineTo(r.right, r.bottom - n)
      ..arcToPoint(Offset(r.right - n, r.bottom), radius: c, clockwise: false)
      ..lineTo(r.left + n, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - n), radius: c, clockwise: false)
      ..lineTo(r.left, r.top + n)
      ..arcToPoint(Offset(r.left + n, r.top), radius: c, clockwise: false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outer = (Offset.zero & size).deflate(1);
    final inner = outer.deflate(6);
    canvas.drawPath(
        _notched(outer, 14), Paint()..color = const Color(0x66FBF7EE));
    canvas.drawPath(
      _notched(outer, 14),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = _AizuColors.gold,
    );
    canvas.drawPath(
      _notched(inner, 9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _AizuColors.gold,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 墨茶に金縁、両端に小さなお城のマークを置いたボタン。
class _CastleButton extends StatelessWidget {
  const _CastleButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const shape = StadiumBorder(
      side: BorderSide(color: _AizuColors.gold, width: 1.5),
    );
    return Material(
      color: _AizuColors.buttonBrown,
      shape: shape,
      elevation: 3,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: shape,
        onTap: onPressed,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const _MiniCastle(right: false),
              Expanded(
                child: Center(
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _AizuColors.goldLight,
                          ),
                        )
                      : Text(
                          label,
                          style: const TextStyle(
                            color: _AizuColors.paperLight,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
              const _MiniCastle(right: true),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// ボタン両端のお城マーク（完成イメージから切り抜いた画像）。
class _MiniCastle extends StatelessWidget {
  const _MiniCastle({required this.right});

  final bool right;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      right
          ? 'assets/images/login_button_castle_right.png'
          : 'assets/images/login_button_castle_left.png',
      width: 46,
      height: 27,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
