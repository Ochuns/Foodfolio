import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';

/// グループ・クーポン管理。
/// 自店舗のグループ（＋紐づくクーポン）を一覧し、新規作成へ遷移する。
class GroupManagementScreen extends StatefulWidget {
  const GroupManagementScreen({super.key});

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  List<Map<String, dynamic>> _groups = [];
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
      if (rows.isEmpty) {
        setState(() {
          _error = '先に店舗を登録してください';
          _loading = false;
        });
        return;
      }
      final rid = (rows.first as Map)['id'] as String;
      final groups = await supabase
          .from('groups')
          .select('id, name, description, group_items(menu_item_id), coupons(title)')
          .eq('restaurant_id', rid)
          .order('created_at');
      if (!mounted) return;
      setState(() {
        _groups = (groups as List).cast<Map<String, dynamic>>();
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
      appBar: AppBar(title: const Text('グループ・クーポン管理')),
      floatingActionButton: _error == null
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/owner/groups/new');
                _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('グループ作成'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_groups.isEmpty) {
      return const Center(child: Text('グループがありません。右下から作成してください。'));
    }
    return ListView.separated(
      itemCount: _groups.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final g = _groups[i];
        final items = (g['group_items'] as List?) ?? [];
        // PostgREST は一対一を object、場合により list で返すため両対応
        final couponRaw = g['coupons'];
        final coupon = couponRaw is List
            ? (couponRaw.isNotEmpty ? couponRaw.first as Map<String, dynamic> : null)
            : couponRaw as Map<String, dynamic>?;
        return ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Text(g['name'] as String? ?? ''),
          subtitle: Text(
            'メニュー ${items.length}件'
            '${coupon != null ? ' ・ クーポン: ${coupon['title']}' : ' ・ クーポン未設定'}',
          ),
          trailing: const Icon(Icons.chevron_right),
          // タップで編集画面へ（グループ＋クーポンの編集・削除）
          onTap: () async {
            await context.push('/owner/groups/${g['id']}/edit');
            _reload();
          },
        );
      },
    );
  }
}
