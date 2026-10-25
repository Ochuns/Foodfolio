import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// チェキ（インスタントフォト）風のカード。
/// 正方形の写真＋下を広くとった白フレーム＋マッキー風の手書きコメント。
/// 写真は [photoBytes]（アップロード前プレビュー）または [photoUrl] を表示する。
class ChekiCard extends StatelessWidget {
  const ChekiCard({
    super.key,
    required this.comment,
    this.photoUrl,
    this.photoBytes,
    this.rating,
    this.rotation = -0.03,
    this.width = 260,
  });

  final String comment;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final int? rating;
  final double rotation;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        width: width,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 正方形の写真部分
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: Colors.grey.shade200,
                  child: _buildPhoto(),
                ),
              ),
              // 下の白フレーム（コメント欄）
              SizedBox(
                height: 92,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (rating != null && rating! > 0) _stars(),
                      const SizedBox(height: 2),
                      Flexible(
                        child: Text(
                          comment,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.yuseiMagic(
                            fontSize: 18,
                            height: 1.15,
                            color: const Color(0xFF222222),
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

  Widget _placeholder() => const Center(
        child: Icon(Icons.restaurant, size: 48, color: Colors.grey),
      );

  Widget _stars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < rating! ? Icons.star : Icons.star_border,
          size: 14,
          color: Colors.amber,
        ),
      ),
    );
  }
}
