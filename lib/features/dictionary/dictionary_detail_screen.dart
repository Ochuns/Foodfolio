import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/app_config.dart';
import '../../core/supabase.dart';
import '../auth/account_button.dart';
import '../cards/card_editor_screen.dart';
import '../cards/cheki_card.dart';

/// 辞典詳細画面（本型）。
/// 表紙 → メニューページ（チェキ or 空き枠）→ 最後にグループ（封印）ページ。
/// メニューをタップしてチェキを作成し、グループページでは自分のチェキを
/// 手動でセットしてクーポンを獲得する（獲得後はリセット、使用チェキは刻印）。
class DictionaryDetailScreen extends StatefulWidget {
  const DictionaryDetailScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<DictionaryDetailScreen> createState() => _DictionaryDetailScreenState();
}

class _DictionaryDetailScreenState extends State<DictionaryDetailScreen> {
  static const _paper = Color(0xFFF3ECDD);
  static const _ink = Color(0xFF3A2A1C);
  static const _cover = Color(0xFF4A3526);

  final _pageController = PageController();
  _DetailData? _data;
  bool _loading = true;
  String? _error;
  int _pageCount = 1;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
        supabase
            .from('cards')
            .select('id, menu_item_id, photo_url, memo, rating, created_at, used_at')
            .eq('restaurant_id', rid)
            .order('created_at', ascending: false),
        supabase
            .from('groups')
            .select(
                'id, name, description, group_items(menu_item_id), coupons(title, description, discount_type, discount_value)')
            .eq('restaurant_id', rid)
            .order('created_at'),
        // RLS により自分の分だけ
        supabase.from('group_selections').select('group_id, menu_item_id, card_id'),
      ]);

      final restaurant = results[0] as Map<String, dynamic>;
      final menus = (results[1] as List).cast<Map<String, dynamic>>();
      final cards = (results[2] as List).cast<Map<String, dynamic>>();
      final groups = (results[3] as List).cast<Map<String, dynamic>>();
      final sels = (results[4] as List).cast<Map<String, dynamic>>();

      final cardsByMenu = <String, List<Map<String, dynamic>>>{};
      final cardById = <String, Map<String, dynamic>>{};
      for (final c in cards) {
        (cardsByMenu[c['menu_item_id'] as String] ??= []).add(c);
        cardById[c['id'] as String] = c;
      }
      final selections = <String, Map<String, String>>{};
      for (final s in sels) {
        (selections[s['group_id'] as String] ??= {})[s['menu_item_id'] as String] =
            s['card_id'] as String;
      }

      if (!mounted) return;
      setState(() {
        _data = _DetailData(
          name: restaurant['name'] as String? ?? '',
          address: restaurant['address'] as String? ?? '',
          menus: menus,
          cardsByMenu: cardsByMenu,
          cardById: cardById,
          groups: groups,
          selections: selections,
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

  // ======================= 来店ジオフェンス =======================

  Future<bool> _ensureAtRestaurant() async {
    if (!AppConfig.enforceVisitLocation) return true;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('現在地を確認しています…'),
      duration: Duration(seconds: 2),
    ));
    final pos = await _getCurrentPosition();
    if (!mounted) return false;
    if (pos == null) {
      await _showInfoDialog('位置情報が必要です',
          'チェキの作成には位置情報の許可が必要です。\nブラウザ／端末の位置情報設定を確認してください。');
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
        await _showInfoDialog('店舗の近くで作成してください',
            'このチェキは店舗の近く（約${AppConfig.visitRadiusM}m以内）でのみ作成できます。\n実際に来店してお試しください。');
        return false;
      }
      return true;
    } catch (e) {
      if (mounted) await _showInfoDialog('確認に失敗しました', '位置の確認に失敗しました。\n$e');
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ======================= チェキ作成/再撮影 =======================

  /// 「同じ店舗では1日1枚」ルールに従い、作成/再撮影/ブロックを振り分ける。
  Future<void> _capture(Map<String, dynamic> menu) async {
    final data = _data;
    if (data == null) return;

    // テスト中は日次制限なし → 常に新規作成
    if (!AppConfig.enforceDailyLimit) {
      await _openEditor(menu);
      return;
    }

    final menuId = menu['id'] as String;
    final today = data.todayCard;

    if (today == null) {
      await _openEditor(menu);
      return;
    }
    if (today['menu_item_id'] == menuId) {
      await _openEditor(menu, reshoot: today);
      return;
    }
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
              child: const Text('閉じる')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('「$otherName」を再撮影')),
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
    if (!await _ensureAtRestaurant()) return;
    if (!mounted) return;

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(reshoot != null
          ? '「${menu['name']}」を再撮影しました'
          : '「${menu['name']}」のチェキを作成しました'),
    ));
  }

  // ======================= 所持チェキの閲覧 =======================

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
              Text(menu['name'] as String? ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetCtx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('${cards.length}枚のチェキ',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
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
                        used: card['used_at'] != null,
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

  Widget _buildSheetButton(BuildContext sheetCtx, Map<String, dynamic> menu) {
    // テスト中は日次制限なし → 常に「もう1枚撮る」
    if (!AppConfig.enforceDailyLimit) {
      return FilledButton.icon(
        onPressed: () {
          Navigator.pop(sheetCtx);
          _capture(menu);
        },
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('もう1枚撮る'),
      );
    }
    final today = _data!.todayCard;
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

  // ======================= グループ（手動セット/獲得） =======================

  /// 空き枠タップ: そのメニューの未使用チェキから選んでセットする。
  Future<void> _pickChekiForSlot(String groupId, String menuItemId) async {
    final data = _data!;
    final candidates = (data.cardsByMenu[menuItemId] ?? const [])
        .where((c) => c['used_at'] == null)
        .toList();
    final menuName = data.menuName(menuItemId);

    if (candidates.isEmpty) {
      await _showInfoDialog('セットできるチェキがありません',
          '「$menuName」の未使用チェキがありません。\n来店してチェキを作成しましょう。\n（クーポンに使ったチェキは再利用できません）');
      return;
    }

    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('「$menuName」にセットするチェキを選ぶ',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetCtx).textTheme.titleMedium),
              const SizedBox(height: 16),
              SizedBox(
                height: 340,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (_, i) {
                    final card = candidates[i];
                    return GestureDetector(
                      onTap: () => Navigator.pop(sheetCtx, card['id'] as String),
                      child: Center(
                        child: ChekiCard(
                          comment: card['memo'] as String? ?? '',
                          photoUrl: card['photo_url'] as String?,
                          rating: card['rating'] as int?,
                          date: _jstDisplayDate(card['created_at']),
                          width: 200,
                          rotation: i.isEven ? -0.02 : 0.02,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text('タップでセット', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    await _setSelection(groupId, menuItemId, chosen);
  }

  Future<void> _setSelection(
      String groupId, String menuItemId, String cardId) async {
    try {
      await supabase.rpc('set_group_selection', params: {
        'p_group_id': groupId,
        'p_menu_item_id': menuItemId,
        'p_card_id': cardId,
      });
      await _reload();
    } catch (e) {
      if (mounted) await _showInfoDialog('セットに失敗しました', '$e');
    }
  }

  Future<void> _clearSelection(String groupId, String menuItemId) async {
    try {
      await supabase.rpc('clear_group_selection', params: {
        'p_group_id': groupId,
        'p_menu_item_id': menuItemId,
      });
      await _reload();
    } catch (e) {
      if (mounted) await _showInfoDialog('解除に失敗しました', '$e');
    }
  }

  Future<void> _claimCoupon(Map<String, dynamic> group) async {
    try {
      final res = await supabase.rpc('claim_group_coupon', params: {
        'p_group_id': group['id'],
      }) as List;
      final code = res.isNotEmpty ? (res.first as Map)['out_code'] as String? : null;
      await _reload();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.emoji_events, color: Colors.amber, size: 40),
          title: const Text('クーポン獲得！'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('「${group['name']}」を達成しました。\nクーポン画面から確認できます。'),
              if (code != null) ...[
                const SizedBox(height: 12),
                SelectableText(code,
                    style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 12),
              const Text('使用したチェキには「使用済」の印が付き、グループ枠はリセットされました。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) await _showInfoDialog('獲得に失敗しました', '$e');
    }
  }

  // ======================= 画面 =======================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cover,
      appBar: AppBar(
        backgroundColor: _cover,
        foregroundColor: Colors.white,
        title: Text(_data?.name ?? '辞典'),
        actions: const [AccountButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Text('取得に失敗しました:\n$_error',
                      style: const TextStyle(color: Colors.white)))
              : _buildBook(_data!),
    );
  }

  Widget _buildBook(_DetailData data) {
    final pages = <Widget>[_coverPage(data)];
    const perPage = 9; // 3×3
    for (var start = 0; start < data.menus.length; start += perPage) {
      final end = math.min(start + perPage, data.menus.length);
      pages.add(_menuPage(data.menus.sublist(start, end), start, data));
    }
    for (final g in data.groups) {
      pages.add(_groupPage(g, data));
    }
    _pageCount = pages.length;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            itemBuilder: (_, i) => _paperWrap(pages[i]),
          ),
        ),
        _pager(),
      ],
    );
  }

  /// 各ページをクリーム色の「紙」で包む
  Widget _paperWrap(Widget child) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: child,
        ),
      ),
    );
  }

  Widget _pager() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            color: Colors.white,
            onPressed: () => _pageController.previousPage(
                duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
            icon: const Icon(Icons.chevron_left),
          ),
          AnimatedBuilder(
            animation: _pageController,
            builder: (context, _) {
              final page = _pageController.hasClients && _pageController.page != null
                  ? _pageController.page!.round() + 1
                  : 1;
              return Text('$page / $_pageCount',
                  style: const TextStyle(color: Colors.white));
            },
          ),
          IconButton(
            color: Colors.white,
            onPressed: () => _pageController.nextPage(
                duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  // ---- 表紙ページ ----
  Widget _coverPage(_DetailData data) {
    final collected = data.collectedIds.length;
    return Column(
      children: [
        const SizedBox(height: 24),
        const Text('食 事 典',
            style: TextStyle(
                color: Color(0x88000000), fontSize: 14, letterSpacing: 8)),
        const SizedBox(height: 24),
        const Icon(Icons.auto_stories, size: 64, color: _ink),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x66C9A227), width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            data.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _ink, fontSize: 26, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        if (data.address.isNotEmpty)
          Text(data.address,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0x99000000))),
        const SizedBox(height: 28),
        Text('収集 $collected / ${data.menus.length}',
            style: const TextStyle(
                color: _ink, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 28),
        const Text('ページをめくって集めよう →',
            style: TextStyle(color: Color(0x99000000))),
      ],
    );
  }

  // ---- メニューページ（3×3・チェキ全体を表示） ----
  Widget _menuPage(
      List<Map<String, dynamic>> slice, int startIndex, _DetailData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeader(title: 'メニュー', icon: Icons.restaurant_menu),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const cols = 3;
            const gap = 10.0;
            final cellW = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: 14,
              children: [
                for (var i = 0; i < slice.length; i++)
                  SizedBox(
                    width: cellW,
                    child: _menuSlot(slice[i], startIndex + i, data, cellW),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _menuSlot(
      Map<String, dynamic> menu, int index, _DetailData data, double w) {
    final id = menu['id'] as String;
    final cards = data.cardsByMenu[id] ?? const [];
    final collected = cards.isNotEmpty;
    final latest = collected ? cards.first : null;
    final no = 'No.${(index + 1).toString().padLeft(3, '0')}';

    return InkWell(
      onTap: collected ? () => _showCardsSheet(menu, cards) : () => _capture(menu),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // チェキ全体（写真＋白フレーム＋コメント＋日付）。未収集は「？」の空きチェキ。
          Stack(
            children: [
              if (collected)
                ChekiCard(
                  comment: latest!['memo'] as String? ?? '',
                  photoUrl: latest['photo_url'] as String?,
                  rating: latest['rating'] as int?,
                  date: _jstDisplayDate(latest['created_at']),
                  used: latest['used_at'] != null,
                  rotation: 0,
                  width: w,
                )
              else
                Opacity(
                  opacity: 0.5,
                  child: ChekiCard(
                    comment: '？',
                    rotation: 0,
                    width: w,
                    showCutGuide: false,
                  ),
                ),
              if (collected && cards.length > 1)
                Positioned(right: 4, top: 4, child: _badge('${cards.length}')),
            ],
          ),
          const SizedBox(height: 4),
          Text(no,
              style: const TextStyle(
                  fontSize: 10, color: Color(0x99000000), letterSpacing: 1)),
          Text(
            menu['name'] as String? ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: collected ? _ink : const Color(0x77000000),
            ),
          ),
        ],
      ),
    );
  }

  // ---- グループ（封印）ページ ----
  Widget _groupPage(Map<String, dynamic> group, _DetailData data) {
    final groupId = group['id'] as String;
    final items = ((group['group_items'] as List?) ?? [])
        .map((e) => (e as Map)['menu_item_id'] as String)
        .toList();
    final sel = data.selections[groupId] ?? const {};
    final filled = items.where((m) {
      final cid = sel[m];
      return cid != null && data.cardById[cid]?['used_at'] == null;
    }).length;
    final complete = items.isNotEmpty && filled == items.length;

    final couponRaw = group['coupons'];
    final coupon = couponRaw is List
        ? (couponRaw.isNotEmpty ? couponRaw.first as Map<String, dynamic> : null)
        : couponRaw as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeader(title: 'グループ（封印）', icon: Icons.workspace_premium),
        const SizedBox(height: 8),
        Text(group['name'] as String? ?? '',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: _ink)),
        if ((group['description'] as String?)?.isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          Text(group['description'] as String,
              style: const TextStyle(color: Color(0x99000000))),
        ],
        const SizedBox(height: 12),
        // クーポン報酬
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x18C9A227),
            border: Border.all(color: const Color(0x66C9A227)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_offer, color: Color(0xFFB8860B)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coupon?['title'] as String? ?? 'クーポン',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: _ink)),
                    if ((coupon?['description'] as String?)?.isNotEmpty ?? false)
                      Text(coupon!['description'] as String,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0x99000000))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('チェキをセット  $filled / ${items.length}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: _ink)),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const cols = 3;
            const gap = 10.0;
            final cellW = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: 14,
              children: [
                for (final m in items)
                  SizedBox(
                    width: cellW,
                    child: _groupSlot(groupId, m, data, cellW),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: complete ? () => _claimCoupon(group) : null,
            icon: const Icon(Icons.emoji_events),
            label: Text(complete ? 'クーポンを獲得する' : 'すべてセットすると獲得できます'),
          ),
        ),
        const SizedBox(height: 8),
        const Text('※ 獲得するとグループはリセットされ、使ったチェキには「使用済」印が付きます。',
            style: TextStyle(fontSize: 11, color: Color(0x99000000))),
      ],
    );
  }

  Widget _groupSlot(
      String groupId, String menuItemId, _DetailData data, double w) {
    final sel = data.selections[groupId] ?? const {};
    final cardId = sel[menuItemId];
    final card = cardId != null ? data.cardById[cardId] : null;
    final valid = card != null && card['used_at'] == null;
    final name = data.menuName(menuItemId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            if (valid)
              // セット済みチェキを全体表示（タップで差し替え）
              GestureDetector(
                onTap: () => _pickChekiForSlot(groupId, menuItemId),
                child: ChekiCard(
                  comment: card['memo'] as String? ?? '',
                  photoUrl: card['photo_url'] as String?,
                  rating: card['rating'] as int?,
                  date: _jstDisplayDate(card['created_at']),
                  rotation: 0,
                  width: w,
                ),
              )
            else
              // 空き枠: 半透明の空きチェキ＋「＋セット」
              GestureDetector(
                onTap: () => _pickChekiForSlot(groupId, menuItemId),
                child: Stack(
                  children: [
                    Opacity(
                      opacity: 0.45,
                      child: ChekiCard(
                          comment: '？',
                          rotation: 0,
                          width: w,
                          showCutGuide: false),
                    ),
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xCC4A3526),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('＋セット',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 11)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (valid)
              Positioned(
                right: 4,
                top: 4,
                child: GestureDetector(
                  onTap: () => _clearSelection(groupId, menuItemId),
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(3),
                    child:
                        const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: _ink)),
      ],
    );
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 10)),
      );
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF3A2A1C)),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF3A2A1C),
                letterSpacing: 2)),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: Color(0x33000000))),
      ],
    );
  }
}

/// 詳細画面で使う取得データ
class _DetailData {
  _DetailData({
    required this.name,
    required this.address,
    required this.menus,
    required this.cardsByMenu,
    required this.cardById,
    required this.groups,
    required this.selections,
  });

  final String name;
  final String address;
  final List<Map<String, dynamic>> menus;

  /// menu_item_id -> そのメニューのカード一覧（新しい順）
  final Map<String, List<Map<String, dynamic>>> cardsByMenu;

  /// card_id -> カード
  final Map<String, Map<String, dynamic>> cardById;
  final List<Map<String, dynamic>> groups;

  /// group_id -> (menu_item_id -> card_id)
  final Map<String, Map<String, String>> selections;

  Set<String> get collectedIds => cardsByMenu.keys.toSet();

  /// 本日(JST)この店舗で作成済みのカード（なければ null）
  Map<String, dynamic>? get todayCard {
    for (final list in cardsByMenu.values) {
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

// ---- 日付ヘルパー（JST基準） ----

DateTime? _parseCardDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

DateTime _jstDay(DateTime t) {
  final jst = t.toUtc().add(const Duration(hours: 9));
  return DateTime(jst.year, jst.month, jst.day);
}

bool _isTodayJst(DateTime t) => _jstDay(t) == _jstDay(DateTime.now());

DateTime? _jstDisplayDate(dynamic v) {
  final t = _parseCardDate(v);
  if (t == null) return null;
  return t.toUtc().add(const Duration(hours: 9));
}
