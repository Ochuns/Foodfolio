import 'package:flutter/material.dart';

import '../../core/supabase.dart';

/// メニュー管理（辞典作成）。
/// 自店舗のメニューを一覧・追加・削除する。
class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  String? _restaurantId;
  List<Map<String, dynamic>> _menus = [];
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
      final menus = await supabase
          .from('menu_items')
          .select('id, name, price, category, sort_order')
          .eq('restaurant_id', rid)
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        _restaurantId = rid;
        _menus = (menus as List).cast<Map<String, dynamic>>();
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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addMenu() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メニュー追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'メニュー名'),
            ),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '価格（円）'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('追加')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty || _restaurantId == null) return;
    try {
      await supabase.from('menu_items').insert({
        'restaurant_id': _restaurantId,
        'name': name,
        'price': int.tryParse(priceCtrl.text.trim()),
        'sort_order': _menus.length,
      });
      await _reload();
    } catch (e) {
      if (mounted) _snack('追加に失敗しました: $e');
    }
  }

  Future<void> _deleteMenu(Map<String, dynamic> menu) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${menu['name']}」を削除しますか？\n関連するグループ・カードも削除されます。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('menu_items').delete().eq('id', menu['id']);
      await _reload();
    } catch (e) {
      if (mounted) _snack('削除に失敗しました: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('メニュー管理')),
      floatingActionButton: _error == null
          ? FloatingActionButton.extended(
              onPressed: _addMenu,
              icon: const Icon(Icons.add),
              label: const Text('メニュー追加'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_menus.isEmpty) {
      return const Center(child: Text('メニューがありません。右下から追加してください。'));
    }
    return ListView.separated(
      itemCount: _menus.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _menus[i];
        final price = m['price'] as int?;
        return ListTile(
          title: Text(m['name'] as String? ?? ''),
          subtitle: price != null ? Text('¥$price') : null,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteMenu(m),
          ),
        );
      },
    );
  }
}
