import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';

/// クーポン表示画面。
/// グループ達成で自動発行された user_coupons を表示する。
/// （会津コイン連携はハッカソンではコード表示まで。支払いは店舗端末で）
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final rows = await supabase
        .from('user_coupons')
        .select('id, code, status, expires_at, coupons(title, description)')
        .order('issued_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                message: 'まだクーポンがありません。\nグループのカードを集めると発行されます。',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) => _CouponCard(data: items[i]),
            );
          },
        ),
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final coupon = data['coupons'] as Map<String, dynamic>?;
    final title = coupon?['title'] as String? ?? 'クーポン';
    final description = coupon?['description'] as String? ?? '';
    final code = data['code'] as String? ?? '';
    final status = data['status'] as String? ?? 'issued';
    final used = status == 'used';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_offer,
                  color: used ? Colors.grey : Colors.deepOrange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (used)
                  const Chip(label: Text('使用済'))
                else
                  const Chip(
                    label: Text('有効'),
                    backgroundColor: Color(0xFFFFE0B2),
                  ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description),
            ],
            const SizedBox(height: 12),
            // 会津コイン連携はコード/QR 表示まで。店舗で提示して使う想定。
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text('提示コード', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 4),
                  SelectableText(
                    code,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          letterSpacing: 2,
                          fontFeatures: const [],
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
