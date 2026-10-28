import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_config.dart';
import '../../core/supabase.dart';
import 'cheki_card.dart';

/// カード作成画面（チェキ風）。
/// 写真を選び、マッキー風フォントでコメントを書き、星評価を付けて保存する。
/// 保存時: 写真を Storage (`card-photos/[uid]/[menuId].jpg`) にアップ → cards に挿入。
class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({
    super.key,
    required this.menuId,
    required this.menuName,
    this.cardId,
    this.initialComment,
    this.initialRating,
    this.initialPhotoUrl,
  });

  final String menuId;
  final String menuName;

  /// 再撮影対象のカードID。null なら新規作成。
  final String? cardId;
  final String? initialComment;
  final int? initialRating;
  final String? initialPhotoUrl;

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  final _comment = TextEditingController();
  Uint8List? _photoBytes;
  String? _photoMime;
  int _rating = 0;
  bool _saving = false;
  String? _error;

  /// 再撮影（既存カードの更新）かどうか
  bool get _isReshoot => widget.cardId != null;

  String get _photoButtonLabel {
    if (_photoBytes != null) return '写真を変更';
    if (_isReshoot) return '写真を撮り直す';
    return AppConfig.cameraOnly ? '写真を撮る' : '写真を追加';
  }

  @override
  void initState() {
    super.initState();
    _comment.text = widget.initialComment ?? '';
    _rating = widget.initialRating ?? 0;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    // 本番(cameraOnly=true)はその場で撮影。テスト中はカメラ/添付を選べる。
    final ImageSource? source =
        AppConfig.cameraOnly ? ImageSource.camera : await _chooseSource();
    if (source == null) return;

    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoBytes = bytes;
      _photoMime = file.mimeType;
    });
  }

  /// テスト時のみ: カメラ撮影かギャラリー添付かを選ばせる。
  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('カメラで撮る'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('ギャラリーから選ぶ（テスト用）'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 再撮影で写真を変えない場合は既存の写真URLを維持
      String? photoUrl = widget.initialPhotoUrl;
      if (_photoBytes != null) {
        final uid = supabase.auth.currentUser!.id;
        // 同じメニューで複数枚持てるよう、カードごとに一意なパスにする
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final path = '$uid/${widget.menuId}-$stamp.jpg';
        await supabase.storage.from('card-photos').uploadBinary(
              path,
              _photoBytes!,
              fileOptions: FileOptions(
                contentType: _photoMime ?? 'image/jpeg',
                upsert: true,
              ),
            );
        photoUrl = supabase.storage.from('card-photos').getPublicUrl(path);
      }

      final memo = _comment.text.trim();
      if (_isReshoot) {
        // 再撮影 = 当日分カードの更新（created_at は変えないので制約に抵触しない）
        await supabase.from('cards').update({
          'memo': memo.isEmpty ? null : memo,
          'rating': _rating == 0 ? null : _rating,
          'photo_url': photoUrl,
        }).eq('id', widget.cardId!);
      } else {
        await supabase.from('cards').insert({
          'menu_item_id': widget.menuId,
          'memo': memo.isEmpty ? null : memo,
          'rating': _rating == 0 ? null : _rating,
          'photo_url': photoUrl,
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      // 一意制約違反（同じ店舗で本日2枚目）はわかりやすい文言に
      setState(() {
        _error = e.code == '23505'
            ? '同じ店舗では1日に1枚までです。本日作成したカードは「再撮影」で更新できます。'
            : e.message;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              '${_isReshoot ? '再撮影' : 'カード作成'}: ${widget.menuName}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ライブプレビュー（チェキ）
            Center(
              child: ChekiCard(
                comment: _comment.text,
                photoBytes: _photoBytes,
                // 再撮影で未選択のうちは既存写真を表示
                photoUrl: _photoBytes == null ? widget.initialPhotoUrl : null,
                rating: _rating,
                date: DateTime.now(),
                width: 260,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_photoButtonLabel),
            ),
            const SizedBox(height: 20),
            Text('コメント（マッキー風）',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              maxLength: 40,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.yuseiMagic(fontSize: 18),
              decoration: const InputDecoration(
                hintText: '例: 最高にうまい塩ラーメン！',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('評価', style: Theme.of(context).textTheme.labelLarge),
            Row(
              children: List.generate(5, (i) {
                final filled = i < _rating;
                return IconButton(
                  onPressed: () => setState(() => _rating = i + 1),
                  icon: Icon(
                    filled ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                  ),
                );
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isReshoot ? '再撮影を保存' : 'カードを作成する'),
            ),
          ],
        ),
      ),
    );
  }
}
