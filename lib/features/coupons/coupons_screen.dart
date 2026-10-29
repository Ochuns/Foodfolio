import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';

/// クーポン表示画面。
/// 辞典のグループでチェキを揃えて獲得した user_coupons を「クーポン券」風に表示する。
/// （会津コイン連携はハッカソンではコード表示まで。支払いは店舗端末で）
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  static const _paper = Color(0xFFF3ECDD);
  static const _ink = Color(0xFF3A2A1C);

  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final rows = await supabase
        .from('user_coupons')
        .select(
            'id, code, status, expires_at, coupons(title, description, discount_type, discount_value)')
        .order('issued_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        title: const Text('クーポン'),
        actions: const [AccountButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _future = _fetch());
          await _future;
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _MessageView(message: '取得に失敗しました:\n${snapshot.error}');
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return const _MessageView(
                message: 'まだクーポンがありません。\n辞典のグループでチェキを揃えて獲得できます。',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _CouponTicket(data: items[i], paper: _paper, ink: _ink),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// クーポン券（チケット）風カード。
/// 左に割引額のスタブ、ミシン目＋切符の切り欠き、右に詳細＋提示コード。
class _CouponTicket extends StatelessWidget {
  const _CouponTicket({
    required this.data,
    required this.paper,
    required this.ink,
  });

  final Map<String, dynamic> data;
  final Color paper;
  final Color ink;

  static const _gold = Color(0xFFC9A227);
  static const double _stubW = 104;

  @override
  Widget build(BuildContext context) {
    final coupon = data['coupons'] as Map<String, dynamic>?;
    final title = coupon?['title'] as String? ?? 'クーポン';
    final description = coupon?['description'] as String? ?? '';
    final code = data['code'] as String? ?? '';
    final used = (data['status'] as String? ?? 'issued') == 'used';
    final exp = _formatDate(data['expires_at']);

    final (value, unit) = _discount(coupon);

    final ticket = Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFBF6EA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold, width: 1.5),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _stub(value, unit),
                const SizedBox(width: _perfGap),
                Expanded(child: _details(context, title, description, code, exp)),
              ],
            ),
          ),
        ),
        // ミシン目（縦の破線）
        Positioned(
          left: _stubW + _perfGap / 2 - 1,
          top: 10,
          bottom: 10,
          child: CustomPaint(
            size: const Size(2, double.infinity),
            painter: _DashedVLinePainter(color: const Color(0x55000000)),
          ),
        ),
        // 切符の切り欠き（上下）
        Positioned(left: _stubW + _perfGap / 2 - 9, top: -9, child: _notch()),
        Positioned(left: _stubW + _perfGap / 2 - 9, bottom: -9, child: _notch()),
        // 使用済みスタンプ
        if (used)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Transform.rotate(
                  angle: -0.25,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: const Color(0xCCB71C1C), width: 3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '使用済',
                      style: TextStyle(
                        color: Color(0xDDB71C1C),
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    // 使用済みは全体を少しあせた見た目に
    return used ? Opacity(opacity: 0.7, child: ticket) : ticket;
  }

  static const double _perfGap = 10;

  // ---- 左スタブ（割引額） ----
  Widget _stub(String value, String unit) {
    return Container(
      width: _stubW,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5A4130), Color(0xFF3A2A1C)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15),
          bottomLeft: Radius.circular(15),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_activity, color: Color(0xFFF1D98A), size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: const TextStyle(
              color: Color(0xFFF7E6C0),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ---- 右側（タイトル・説明・コード） ----
  Widget _details(BuildContext context, String title, String description,
      String code, String? exp) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer, size: 16, color: _gold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0x99000000)),
            ),
          ],
          const SizedBox(height: 10),
          // 提示コード
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x33C9A227)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('提示コード',
                    style: TextStyle(fontSize: 10, color: Color(0x99000000))),
                const SizedBox(height: 2),
                SelectableText(
                  code,
                  style: TextStyle(
                    color: ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.payments_outlined,
                  size: 14, color: ink.withValues(alpha: 0.6)),
              const SizedBox(width: 4),
              Text('会津コイン対応',
                  style: TextStyle(
                      fontSize: 11, color: ink.withValues(alpha: 0.6))),
              const Spacer(),
              if (exp != null)
                Text('有効期限 $exp',
                    style:
                        const TextStyle(fontSize: 11, color: Color(0x99000000))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notch() => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(color: paper, shape: BoxShape.circle),
      );

  // 割引の表示（大きい数字＋単位）
  (String, String) _discount(Map<String, dynamic>? coupon) {
    final type = coupon?['discount_type'] as String?;
    final raw = coupon?['discount_value'];
    final v = raw is num ? raw : num.tryParse('${raw ?? ''}');
    if (v == null) return ('特典', 'クーポン');
    final n = v % 1 == 0 ? v.toInt().toString() : v.toString();
    if (type == 'percent') return (n, '％引き');
    if (type == 'amount') return (n, '円引き');
    return (n, 'OFF');
  }

  String? _formatDate(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    final t = DateTime.tryParse(v);
    if (t == null) return null;
    final j = t.toUtc().add(const Duration(hours: 9));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${j.year}.${two(j.month)}.${two(j.day)}';
  }
}

/// 縦の破線（ミシン目）を描く。
class _DashedVLinePainter extends CustomPainter {
  _DashedVLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const dash = 5.0, gap = 4.0;
    var y = 0.0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(
          Offset(x, y), Offset(x, math.min(y + dash, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedVLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 中央寄せのメッセージ（Pull-to-refresh を効かせるためスクロール可能に）
class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF3A2A1C))),
          ),
        ),
      ],
    );
  }
}
