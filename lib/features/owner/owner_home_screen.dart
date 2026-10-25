import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';

/// 店舗オーナーのホーム。
/// 店舗未登録なら登録を促し、登録済みなら各管理画面への入口を出す。
class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  Map<String, dynamic>? _restaurant;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await supabase.rpc('get_my_restaurant') as List;
      if (!mounted) return;
      setState(() {
        _restaurant =
            rows.isEmpty ? null : (rows.first as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('店舗管理'),
        actions: const [AccountButton()],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('取得に失敗しました:\n$_error'));

    final r = _restaurant;
    if (r == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.store_mall_directory_outlined,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('まだ店舗が登録されていません。', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await context.push('/owner/restaurant');
                  _reload();
                },
                icon: const Icon(Icons.add),
                label: const Text('店舗を登録する'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['name'] as String? ?? '',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(r['address'] as String? ?? ''),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: const Text('店舗情報を編集'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await context.push('/owner/restaurant');
              _reload();
            },
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('メニュー管理（辞典を作る）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/owner/menus'),
          ),
          ListTile(
            leading: const Icon(Icons.local_offer_outlined),
            title: const Text('グループ・クーポン管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/owner/groups'),
          ),
        ],
      ),
    );
  }
}
