import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/app_config.dart';
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
        // RLS により自分のカードだけが返る（新しい順）
        supabase
            .from('cards')
            .select('id, menu_item_id, photo_url, memo, rating, created_at')
            .eq('restaurant_id', rid)
            .order('created_at', ascending: false),
        supabase
            .from('groups')
            .select('id, name, description, group_items(menu_item_id)')
            .eq('restaurant_id', rid),
      ]);

      final restaurant = results[0] as Map<String, dynamic>;
      final menus = (results[1] as List).cast<Map<String, dynamic>>();
      final cards = (results[2] as List).cast<Map<String, dynamic>>();
      final groups = (results[3] as List).cast<Map<String, dynamic>>();

      // メニューごとに複数枚のカードをまとめる（新しい順のまま）
      final cardsByMenu = <String, List<Map<String, dynamic>>>{};
      for (final c in cards) {
        (cardsByMenu[c['menu_item_id'] as String] ??= []).add(c);
      }

      if (!mounted) return;
      setState(() {
        _data = _DetailData(
          name: restaurant['name'] as String? ?? '',
          address: restaurant['address'] as String? ?? '',
          menus: menus,
          cards: cardsByMenu,
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

  /// 来店ジオフェンス判定。店舗の近く（約 [AppConfig.visitRadiusM] m）にいれば true。
  /// テスト中（AppConfig.enforceVisitLocation=false）は常に true。
  Future<bool> _ensureAtRestaurant() async {
    if (!AppConfig.enforceVisitLocation) return true;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('現在地を確認しています…'),
      duration: Duration(seconds: 2),
    ));

    final pos = await _getCurrentPosition();
    if (!mounted) return false;
    if (pos == null) {
      await _showInfoDialog(
        '位置情報が必要です',
        'チェキの作成には位置情報の許可が必要です。\nブラウザ／端末の位置情報設定を確認してください。',
      );
      return false;
    }

    try {
      final within = await supabase.rpc('is_within_restaurant', params: {
        'r_id': widget.restaurantId,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'radius_m': AppConfig.visitRadiusM,
      }) as bool;
      if (!mounted) return false;
      if (!within) {
        await _showInfoDialog(
          '店舗の近くで作成してください',
          'このチェキは店舗の近く（約${AppConfig.visitRadiusM}m以内）でのみ作成できます。\n実際に来店してお試しください。',
        );
        return false;
      }
      return true;
    } catch (e) {
      if (mounted) {
        await _showInfoDialog('確認に失敗しました', '位置の確認に失敗しました。\n$e');
      }
      return false;
    }
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> _showInfoDialog(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.location_on_outlined),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// メニューをタップ/「撮る」操作の入口。
  /// 「同じ店舗では1日1枚」ルールに従い、作成 / 再撮影 / ブロックを振り分ける。
  Future<void> _capture(Map<String, dynamic> menu) async {
    final data = _data;
    if (data == null) return;
    final menuId = menu['id'] as String;
    final today = data.todayCard;

    if (today == null) {
      // 本日この店舗で未作成 → 新規作成
      await _openEditor(menu);
      return;
    }
    if (today['menu_item_id'] == menuId) {
      // 本日分がこのメニュー → 再撮影（上書き）
      await _openEditor(menu, reshoot: today);
      return;
    }
    // 本日分が別メニュー → 1日1枚ルールでブロック（そのメニューの再撮影は案内）
    final otherId = today['menu_item_id'] as String;
    final otherName = data.menuName(otherId);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        title: const Text('本日は作成済みです'),
        content: Text(
          '同じ店舗では1日に1枚までです。\n'
          '本日はこの店舗で「$otherName」のチェキを作成済みです。\n'
          '本日分は再撮影のみ可能です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('閉じる'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('「$otherName」を再撮影'),
          ),
        ],
      ),
    );
    if (go != true) return;
    final otherMenu = data.menuById(otherId);
    if (otherMenu != null) await _openEditor(otherMenu, reshoot: today);
  }

  Future<void> _openEditor(
    Map<String, dynamic> menu, {
    Map<String, dynamic>? reshoot,
  }) async {
    // 来店ジオフェンス: 店舗の近くにいるときだけ作成/再撮影できる
    if (!await _ensureAtRestaurant()) return;
    if (!mounted) return;

    final data = _data;
    final before = data != null ? _completedGroupIds(data) : <String>{};

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CardEditorScreen(
          menuId: menu['id'] as String,
          menuName: menu['name'] as String? ?? '',
          cardId: reshoot?['id'] as String?,
          initialComment: reshoot?['memo'] as String?,
          initialRating: reshoot?['rating'] as int?,
          initialPhotoUrl: reshoot?['photo_url'] as String?,
        ),
      ),
    );
    if (saved != true) return;

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
      final msg = reshoot != null
          ? '「${menu['name']}」を再撮影しました'
          : '「${menu['name']}」のカードを作成しました';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// メニューの所持チェキ一覧（横スクロール）＋「もう1枚撮る」導線
  void _showCardsSheet(
      Map<String, dynamic> menu, List<Map<String, dynamic>> cards) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                menu['name'] as String? ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(sheetCtx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${cards.length}枚のチェキ',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 340,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (_, i) {
                    final card = cards[i];
                    return Center(
                      child: ChekiCard(
                        comment: card['memo'] as String? ?? '',
                        photoUrl: card['photo_url'] as String?,
                        rating: card['rating'] as int?,
                        date: _jstDisplayDate(card['created_at']),
                        width: 220,
                        rotation: i.isEven ? -0.02 : 0.02,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSheetButton(sheetCtx, menu),
            ],
          ),
        ),
      ),
    );
  }

  /// シート下部のボタン。本日の作成状況に応じてラベル/挙動を変える。
  Widget _buildSheetButton(
      BuildContext sheetCtx, Map<String, dynamic> menu) {
    final data = _data!;
    final today = data.todayCard;
    final thisMenu = today != null && today['menu_item_id'] == menu['id'];

    final String label;
    if (thisMenu) {
      label = '本日分を再撮影する';
    } else if (today != null) {
      label = '本日は別メニューで作成済み';
    } else {
      label = 'もう1枚撮る（本日分）';
    }

    return FilledButton.icon(
      onPressed: () {
        Navigator.pop(sheetCtx);
        _capture(menu);
      },
      icon: Icon(thisMenu ? Icons.refresh : Icons.add_a_photo_outlined),
      label: Text(label),
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
            final cards = data.cards[id] ?? const [];
            final done = cards.isNotEmpty;
            final price = m['price'] as int?;
            final subParts = <String>[
              if (price != null) '¥$price',
              if (cards.length > 1) '${cards.length}枚所持',
            ];
            return ListTile(
              leading: _leading(cards),
              title: Text(m['name'] as String? ?? ''),
              subtitle: subParts.isEmpty ? null : Text(subParts.join('　')),
              trailing: done
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('収集済',
                            style: TextStyle(color: Colors.green)),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              onTap:
                  done ? () => _showCardsSheet(m, cards) : () => _capture(m),
            );
          }),
        ],
      ),
    );
  }

  Widget _leading(List<Map<String, dynamic>> cards) {
    if (cards.isEmpty) {
      return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
    }
    // 最新（先頭）のカードのサムネイルを代表表示
    final url = cards.first['photo_url'] as String?;
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

  /// menu_item_id -> そのメニューのカード一覧（新しい順）
  final Map<String, List<Map<String, dynamic>>> cards;
  final List<Map<String, dynamic>> groups;

  /// 1枚以上カードがある（＝収集済み）メニューIDの集合
  Set<String> get collectedIds => cards.keys.toSet();

  /// 本日(JST)この店舗で作成済みのカード（なければ null）。
  /// 一意制約により店舗内では最大1枚。
  Map<String, dynamic>? get todayCard {
    for (final list in cards.values) {
      for (final c in list) {
        final d = _parseCardDate(c['created_at']);
        if (d != null && _isTodayJst(d)) return c;
      }
    }
    return null;
  }

  Map<String, dynamic>? menuById(String id) {
    for (final m in menus) {
      if (m['id'] == id) return m;
    }
    return null;
  }

  String menuName(String id) => menuById(id)?['name'] as String? ?? 'メニュー';
}

// ---- 日付ヘルパー（JST基準で「本日」を判定／表示） ----

DateTime? _parseCardDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

/// 任意の日時を JST の暦日(0時)に丸める。
DateTime _jstDay(DateTime t) {
  final jst = t.toUtc().add(const Duration(hours: 9));
  return DateTime(jst.year, jst.month, jst.day);
}

bool _isTodayJst(DateTime t) => _jstDay(t) == _jstDay(DateTime.now());

/// チェキ表示用: created_at を JST の壁時計時刻に変換（年月日が JST になる）。
DateTime? _jstDisplayDate(dynamic v) {
  final t = _parseCardDate(v);
  if (t == null) return null;
  return t.toUtc().add(const Duration(hours: 9));
}
