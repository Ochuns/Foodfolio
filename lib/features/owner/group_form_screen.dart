import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';

/// グループ作成フォーム。
/// グループ名・対象メニュー・達成時クーポンを1画面で登録する。
/// 保存時: groups → group_items → coupons の順に作成する。
class GroupFormScreen extends StatefulWidget {
  const GroupFormScreen({super.key});

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _groupName = TextEditingController();
  final _groupDesc = TextEditingController();
  final _couponTitle = TextEditingController();
  final _couponDesc = TextEditingController();
  final _discountValue = TextEditingController(text: '200');
  final _validDays = TextEditingController(text: '30');

  List<Map<String, dynamic>> _menus = [];
  final Set<String> _selected = {};
  String? _restaurantId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
          .select('id, name')
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

  @override
  void dispose() {
    _groupName.dispose();
    _groupDesc.dispose();
    _couponTitle.dispose();
    _couponDesc.dispose();
    _discountValue.dispose();
    _validDays.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      setState(() => _error = 'メニューを1つ以上選択してください');
      return;
    }
    if (_restaurantId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 1) グループ作成
      final group = await supabase
          .from('groups')
          .insert({
            'restaurant_id': _restaurantId,
            'name': _groupName.text.trim(),
            'description': _groupDesc.text.trim(),
          })
          .select('id')
          .single();
      final gid = group['id'] as String;

      // 2) グループに属するメニューを登録
      await supabase.from('group_items').insert(
            _selected.map((mid) => {'group_id': gid, 'menu_item_id': mid}).toList(),
          );

      // 3) 達成時クーポンを作成
      await supabase.from('coupons').insert({
        'group_id': gid,
        'title': _couponTitle.text.trim(),
        'description': _couponDesc.text.trim(),
        'discount_type': 'amount',
        'discount_value': int.tryParse(_discountValue.text.trim()),
        'valid_days': int.tryParse(_validDays.text.trim()),
      });

      if (!mounted) return;
      context.pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('グループ作成')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Label('グループ'),
                    TextFormField(
                      controller: _groupName,
                      decoration: const InputDecoration(
                          labelText: 'グループ名（例: 塩ラーメン制覇）',
                          border: OutlineInputBorder()),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _groupDesc,
                      decoration: const InputDecoration(
                          labelText: '説明', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 20),
                    const _Label('対象メニュー（集めると達成）'),
                    if (_menus.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('メニューがありません。先にメニューを追加してください。'),
                      )
                    else
                      ..._menus.map((m) {
                        final id = m['id'] as String;
                        return CheckboxListTile(
                          value: _selected.contains(id),
                          title: Text(m['name'] as String? ?? ''),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                        );
                      }),
                    const SizedBox(height: 20),
                    const _Label('達成時クーポン'),
                    TextFormField(
                      controller: _couponTitle,
                      decoration: const InputDecoration(
                          labelText: 'クーポン名', border: OutlineInputBorder()),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _couponDesc,
                      decoration: const InputDecoration(
                          labelText: '内容（例: 次回200円引き）',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _discountValue,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: '割引額（円）',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _validDays,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: '有効日数', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('作成する'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? '入力してください' : null;
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
}
