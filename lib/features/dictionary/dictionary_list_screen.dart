import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';

/// 辞典（＝店舗）一覧画面。
/// 店舗を「閉じた本（辞典）」の表紙として並べ、タップで各店舗の辞典へ。
class DictionaryListScreen extends StatefulWidget {
  const DictionaryListScreen({super.key});

  @override
  State<DictionaryListScreen> createState() => _DictionaryListScreenState();
}

class _DictionaryListScreenState extends State<DictionaryListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchRestaurants();
  }

  Future<List<Map<String, dynamic>>> _fetchRestaurants() async {
    final rows = await supabase
        .from('restaurants')
        .select('id, name, address, image_url')
        .order('created_at');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3ECDD),
      appBar: AppBar(
        title: const Text('食事典'),
        actions: const [AccountButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _future = _fetchRestaurants());
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
                message: 'まだ辞典がありません。\n（店舗が登録されると表示されます）',
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 0.70,
                crossAxisSpacing: 16,
                mainAxisSpacing: 20,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final r = items[i];
                return _BookCover(
                  title: r['name'] as String? ?? '',
                  onTap: () => context.push('/restaurant/${r['id']}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 閉じた辞典の表紙。背表紙・帯・店名を描く。
class _BookCover extends StatelessWidget {
  const _BookCover({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(8),
            bottomRight: Radius.circular(8),
            topLeft: Radius.circular(3),
            bottomLeft: Radius.circular(3),
          ),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF3A2A1C), Color(0xFF5A4130), Color(0xFF4A3526)],
            stops: [0.0, 0.12, 1.0],
          ),
          boxShadow: const [
            BoxShadow(
                color: Colors.black38, blurRadius: 8, offset: Offset(2, 4)),
          ],
        ),
        child: Stack(
          children: [
            // 背表紙のライン
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: const Color(0x33000000)),
            ),
            // 外周の金枠
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x66C9A227), width: 1.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 中央の帯＋店名
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 14, 16),
              child: Column(
                children: [
                  const Text(
                    '食事典',
                    style: TextStyle(
                      color: Color(0xAAE8D9A8),
                      fontSize: 11,
                      letterSpacing: 4,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3ECDD),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 3),
                      ],
                    ),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF3A2A1C),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.auto_stories,
                      color: Color(0x88E8D9A8), size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中央寄せのメッセージ表示（Pull-to-refresh を効かせるためスクロール可能にする）
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
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
