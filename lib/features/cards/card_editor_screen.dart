import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  final String menuId;
  final String menuName;

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

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoBytes = bytes;
      _photoMime = file.mimeType;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? photoUrl;
      if (_photoBytes != null) {
        final uid = supabase.auth.currentUser!.id;
        final path = '$uid/${widget.menuId}.jpg';
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
      await supabase.from('cards').insert({
        'menu_item_id': widget.menuId,
        'memo': memo.isEmpty ? null : memo,
        'rating': _rating == 0 ? null : _rating,
        'photo_url': photoUrl,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: Text('カード作成: ${widget.menuName}')),
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
                rating: _rating,
                width: 260,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_photoBytes == null ? '写真を選ぶ' : '写真を変更'),
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
                  : const Text('カードを作成する'),
            ),
          ],
        ),
      ),
    );
  }
}
