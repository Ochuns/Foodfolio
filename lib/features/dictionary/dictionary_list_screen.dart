import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';

/// 辞典（＝店舗）一覧画面。
/// Supabase の restaurants テーブルから取得して表示する。
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
      appBar: AppBar(
        title: const Text('辞典一覧'),
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
                message: 'まだ辞典がありません。\n（seed データを投入すると表示されます）',
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = items[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.store)),
                  title: Text(r['name'] as String? ?? ''),
                  subtitle: Text(r['address'] as String? ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/dictionaries/${r['id']}'),
                );
              },
            );
          },
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
