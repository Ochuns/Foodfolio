import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';
import '../cards/card_editor_screen.dart';
import '../cards/cheki_card.dart';

/// 辞典詳細画面。
/// 1店舗のメニュー一覧＋自分の収集状況＋グループ進捗を表示する。
/// 未収集メニューをタップ → チェキ風カード作成。収集済みは保存したチェキを表示。
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
        supabase
            .from('cards')
            .select('menu_item_id, photo_url, memo, rating')
            .eq('restaurant_id', rid),
        supabase
            .from('groups')
            .select('id, name, description, group_items(menu_item_id)')
            .eq('restaurant_id', rid),
      ]);

      final restaurant = results[0] as Map<String, dynamic>;
      final menus = (results[1] as List).cast<Map<String, dynamic>>();
      final cards = (results[2] as List).cast<Map<String, dynamic>>();
      final groups = (results[3] as List).cast<Map<String, dynamic>>();

      final cardByMenu = <String, Map<String, dynamic>>{
        for (final c in cards) c['menu_item_id'] as String: c,
      };

      if (!mounted) return;
      setState(() {
        _data = _DetailData(
          name: restaurant['name'] as String? ?? '',
          address: restaurant['address'] as String? ?? '',
          menus: menus,
          cards: cardByMenu,
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
    final collected = data.collectedIds;
    final result = <String>{};
    for (final g in data.groups) {
      final items = (g['group_items'] as List).cast<Map<String, dynamic>>();
      if (items.isEmpty) continue;
      final allDone =
          items.every((i) => collected.contains(i['menu_item_id']));
      if (allDone) result.add(g['id'] as String);
    }
    return result;
  }

  Future<void> _openEditor(Map<String, dynamic> menu) async {
    final data = _data;
    final before = data != null ? _completedGroupIds(data) : <String>{};

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CardEditorScreen(
          menuId: menu['id'] as String,
          menuName: menu['name'] as String? ?? '',
        ),
      ),
    );
    if (created != true) return;

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
        SnackBar(content: Text('「${menu['name']}」のカードを作成しました')),
      );
    }
  }

  void _showCheki(Map<String, dynamic> menu, Map<String, dynamic> card) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChekiCard(
              comment: card['memo'] as String? ?? '',
              photoUrl: card['photo_url'] as String?,
              rating: card['rating'] as int?,
              width: 300,
              rotation: -0.02,
            ),
            const SizedBox(height: 12),
            Text(
              menu['name'] as String? ?? '',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
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
          const _SectionTitle('メニュー（タップでチェキ作成）'),
          ...data.menus.map((m) {
            final id = m['id'] as String;
            final card = data.cards[id];
            final done = card != null;
            final price = m['price'] as int?;
            return ListTile(
              leading: _leading(card),
              title: Text(m['name'] as String? ?? ''),
              subtitle: price != null ? Text('¥$price') : null,
              trailing: done
                  ? const Text('収集済', style: TextStyle(color: Colors.green))
                  : const Icon(Icons.add_a_photo_outlined),
              onTap: done ? () => _showCheki(m, card) : () => _openEditor(m),
            );
          }),
        ],
      ),
    );
  }

  Widget _leading(Map<String, dynamic>? card) {
    if (card == null) {
      return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
    }
    final url = card['photo_url'] as String?;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.check_circle, color: Colors.green),
        ),
      );
    }
    return const Icon(Icons.check_circle, color: Colors.green);
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
    required this.cards,
    required this.groups,
  });

  final String name;
  final String address;
  final List<Map<String, dynamic>> menus;

  /// menu_item_id -> カード情報(photo_url/memo/rating)
  final Map<String, Map<String, dynamic>> cards;
  final List<Map<String, dynamic>> groups;

  Set<String> get collectedIds => cards.keys.toSet();
}
