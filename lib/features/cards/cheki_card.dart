import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// チェキ（インスタントフォト）風のカード。
/// 正方形の写真＋下を広くとった白フレーム＋マッキー風の手書きコメント。
/// 写真は [photoBytes]（アップロード前プレビュー）または [photoUrl] を表示する。
/// 各寸法は [width] に比例してスケールするので、小さく並べても崩れない。
/// [used]=true のときは切符のように左下角へ切り込み（カット）を入れ、
/// 写真は隠さずに「使用済み」であることを示す。
class ChekiCard extends StatelessWidget {
  const ChekiCard({
    super.key,
    required this.comment,
    this.photoUrl,
    this.photoBytes,
    this.rating,
    this.date,
    this.used = false,
    this.showCutGuide = true,
    this.rotation = -0.03,
    this.width = 260,
  });

  /// スケール基準幅（この幅のときに各寸法が等倍）
  static const double _baseWidth = 260;

  final String comment;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final int? rating;

  /// クーポン獲得に使用済み（切符のような切り込みを入れる）
  final bool used;

  /// 未使用時に、左下角の「切り取り線（破線）」を表示するか。
  /// 空き枠プレースホルダー等では false にする。
  final bool showCutGuide;

  /// 撮影日（白フレーム右下にインスタックス風の日付スタンプとして表示）
  final DateTime? date;
  final double rotation;
  final double width;

  double get _s => width / _baseWidth;

  String get _dateText {
    final d = date;
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${two(d.month)}.${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final pad = 12 * s;
    return Transform.rotate(
      angle: rotation,
      child: PhysicalShape(
        clipper: _ChekiClipper(notch: used ? width * 0.13 : 0),
        clipBehavior: Clip.antiAlias,
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black45,
        child: SizedBox(
          width: width,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                // 正方形の写真部分（使用済みでも写真は隠さない）
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    color: Colors.grey.shade200,
                    child: _buildPhoto(),
                  ),
                ),
                // 下の白フレーム（評価＋使用済タグ / コメント / 撮影日）
                SizedBox(
                  height: 104 * s,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(8 * s, 8 * s, 8 * s, 6 * s),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (rating != null && rating! > 0) _stars(s),
                            const Spacer(),
                            if (used) _usedTag(s),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              comment,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.yuseiMagic(
                                fontSize: 18 * s,
                                height: 1.15,
                                color: const Color(0xFF222222),
                              ),
                            ),
                          ),
                        ),
                        // 右下に撮影日（インスタックス風の日付スタンプ）
                        if (date != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _dateText,
                              style: GoogleFonts.yuseiMagic(
                                fontSize: 13 * s,
                                color: const Color(0xFFE8A13A),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
              // 未使用のうちは左下角に「切り取り線（破線）」を表示
              if (!used && showCutGuide)
                Positioned.fill(
                  child: CustomPaint(painter: _CutGuidePainter()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    if (photoBytes != null) {
      return Image.memory(photoBytes!, fit: BoxFit.cover);
    }
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Center(
        child: Icon(Icons.restaurant, size: 48 * _s, color: Colors.grey),
      );

  /// 使用済みを示す小さな赤タグ（写真を隠さない）
  Widget _usedTag(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5 * s, vertical: 1 * s),
      decoration: BoxDecoration(
        border: Border.all(
            color: const Color(0xCCD32F2F), width: (1.5 * s).clamp(1.0, 1.5)),
        borderRadius: BorderRadius.circular(3 * s),
      ),
      child: Text(
        '使用済',
        style: TextStyle(
          color: const Color(0xDDB71C1C),
          fontWeight: FontWeight.w900,
          fontSize: 11 * s,
          letterSpacing: 1 * s,
        ),
      ),
    );
  }

  Widget _stars(double s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < rating! ? Icons.star : Icons.star_border,
          size: 14 * s,
          color: Colors.amber,
        ),
      ),
    );
  }
}

/// チェキの外形クリッパー。[notch] > 0 のとき左下角を斜めにカット（切符の切り込み）。
class _ChekiClipper extends CustomClipper<Path> {
  _ChekiClipper({required this.notch});

  /// 左下の切り込みの大きさ（0 で切り込みなし）
  final double notch;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (notch <= 0) {
      path.addRect(Offset.zero & size);
      return path;
    }
    final n = notch.clamp(0.0, size.shortestSide / 2);
    path
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(n, size.height) // 下辺を左から n 手前まで
      ..lineTo(0, size.height - n) // 左辺を下から n 上まで（斜めにカット）
      ..close();
    return path;
  }

  @override
  bool shouldReclip(_ChekiClipper oldClipper) => oldClipper.notch != notch;
}

/// 未使用時に、将来切り取られる左下角を「破線（ミシン目）」で示すペインター。
class _CutGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final n = size.width * 0.13;
    if (n <= 0) return;
    final p1 = Offset(0, size.height - n);
    final p2 = Offset(n, size.height);
    final total = (p2 - p1).distance;
    if (total <= 0) return;
    final s = size.width / 260;
    final dir = Offset((p2.dx - p1.dx) / total, (p2.dy - p1.dy) / total);
    final dash = 4.0 * s;
    final gap = 3.0 * s;
    final paint = Paint()
      ..color = const Color(0x99000000)
      ..strokeWidth = (1.2 * s).clamp(0.6, 1.4)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    var d = 0.0;
    while (d < total) {
      final start = p1 + dir * d;
      final end = p1 + dir * math.min(d + dash, total);
      canvas.drawLine(start, end, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
