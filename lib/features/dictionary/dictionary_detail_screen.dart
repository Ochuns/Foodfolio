import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';

/// 辞典詳細画面。
/// 1店舗のメニュー一覧＋自分の収集状況＋グループ進捗を表示し、
/// メニューをタップするとカードを作成（辞典を埋める）できる。
/// グループが揃うと DB トリガーがクーポンを自動発行し、その場で通知する。
class DictionaryDetailScreen extends StatefulWidget {
  const DictionaryDetailScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<DictionaryDetailScreen> createState() => _DictionaryDetailScreenState();
}

class _DictionaryDetailScreenState extends State<DictionaryDetailScreen> {
  _DetailData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rid = widget.restaurantId;
    try {
      final results = await Future.wait([
        supabase.from('restaurants').select('name, address').eq('id', rid).single(),
        supabase
            .from('menu_items')
            .select('id, name, price, category')
            .eq('restaurant_id', rid)
            .order('sort_order'),
        // RLS により自分のカードだけが返る
        supabase.from('cards').select('menu_item_id').eq('restaurant_id', rid),
        supabase
            .from('groups')
            .select('id, name, description, group_items(menu_item_id)')
            .eq('restaurant_id', rid),
      ]);

      final restaurant = results[0] as Map<String, dynamic>;
      final menus = (results[1] as List).cast<Map<String, dynamic>>();
      final cards = (results[2] as List).cast<Map<String, dynamic>>();
      final groups = (results[3] as List).cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() {
        _data = _DetailData(
          name: restaurant['name'] as String? ?? '',
          address: restaurant['address'] as String? ?? '',
          menus: menus,
          collectedIds: cards.map((c) => c['menu_item_id'] as String).toSet(),
          groups: groups,
        );
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

  /// 完成しているグループのID集合を返す
  Set<String> _completedGroupIds(_DetailData data) {
    final result = <String>{};
    for (final g in data.groups) {
      final items = (g['group_items'] as List).cast<Map<String, dynamic>>();
      if (items.isEmpty) continue;
      final allDone =
          items.every((i) => data.collectedIds.contains(i['menu_item_id']));
      if (allDone) result.add(g['id'] as String);
    }
    return result;
  }

  Future<void> _createCard(Map<String, dynamic> menu) async {
    final menuId = menu['id'] as String;
    final menuName = menu['name'] as String? ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('カードを作成'),
        content: Text('「$menuName」のカードを作成しますか？\n（この店で注文した記録になります）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('作成する'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final before = _data != null ? _completedGroupIds(_data!) : <String>{};

    try {
      await supabase.from('cards').insert({'menu_item_id': menuId});
      await _reload();

      if (!mounted) return;
      final after = _data != null ? _completedGroupIds(_data!) : <String>{};
      final newlyCompleted = after.difference(before);

      if (newlyCompleted.isNotEmpty) {
        final names = _data!.groups
            .where((g) => newlyCompleted.contains(g['id']))
            .map((g) => g['name'] as String? ?? '')
            .join('・');
        await _showCouponDialog(names);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「$menuName」のカードを作成しました')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('カード作成に失敗しました: $e')),
      );
    }
  }

  Future<void> _showCouponDialog(String groupNames) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.emoji_events, color: Colors.amber, size: 40),
        title: const Text('クーポン獲得！'),
        content: Text('「$groupNames」を達成しました。\nクーポン画面から確認できます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_data?.name ?? '辞典'),
        actions: const [AccountButton()],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('取得に失敗しました:\n$_error'));
    }
    final data = _data!;

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.address, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  '収集: ${data.collectedIds.length} / ${data.menus.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
          if (data.groups.isNotEmpty) ...[
            const _SectionTitle('グループ'),
            ...data.groups
                .map((g) => _GroupTile(group: g, collected: data.collectedIds)),
          ],
          const _SectionTitle('メニュー（タップでカード作成）'),
          ...data.menus.map((m) {
            final id = m['id'] as String;
            final done = data.collectedIds.contains(id);
            final price = m['price'] as int?;
            return ListTile(
              leading: Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? Colors.green : Colors.grey,
              ),
              title: Text(m['name'] as String? ?? ''),
              subtitle: price != null ? Text('¥$price') : null,
              trailing: done
                  ? const Text('収集済', style: TextStyle(color: Colors.green))
                  : const Icon(Icons.add_circle_outline),
              enabled: !done,
              onTap: done ? null : () => _createCard(m),
            );
          }),
        ],
      ),
    );
  }
}

/// グループ1件の進捗タイル
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.collected});

  final Map<String, dynamic> group;
  final Set<String> collected;

  @override
  Widget build(BuildContext context) {
    final items = (group['group_items'] as List).cast<Map<String, dynamic>>();
    final total = items.length;
    final done = items.where((i) => collected.contains(i['menu_item_id'])).length;
    final ratio = total == 0 ? 0.0 : done / total;
    final complete = total > 0 && done == total;

    return ListTile(
      leading: Icon(
        complete ? Icons.emoji_events : Icons.flag_outlined,
        color: complete ? Colors.amber : null,
      ),
      title: Text(group['name'] as String? ?? ''),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: ratio),
            const SizedBox(height: 4),
            Text(complete ? '達成！クーポン獲得' : '$done / $total'),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 詳細画面で使う取得データ
class _DetailData {
  _DetailData({
    required this.name,
    required this.address,
    required this.menus,
    required this.collectedIds,
    required this.groups,
  });

  final String name;
  final String address;
  final List<Map<String, dynamic>> menus;
  final Set<String> collectedIds;
  final List<Map<String, dynamic>> groups;
}
