import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';

/// 店舗の登録 / 編集フォーム。
/// location(PostGIS) は lat/lng を upsert_my_restaurant RPC に渡して生成する。
class RestaurantFormScreen extends StatefulWidget {
  const RestaurantFormScreen({super.key});

  @override
  State<RestaurantFormScreen> createState() => _RestaurantFormScreenState();
}

class _RestaurantFormScreenState extends State<RestaurantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  // 会津若松駅周辺を初期値に
  final _lat = TextEditingController(text: '37.4948');
  final _lng = TextEditingController(text: '139.9296');

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
      if (rows.isNotEmpty) {
        final r = (rows.first as Map).cast<String, dynamic>();
        _name.text = r['name'] as String? ?? '';
        _description.text = r['description'] as String? ?? '';
        _address.text = r['address'] as String? ?? '';
        if (r['lat'] != null) _lat.text = (r['lat'] as num).toString();
        if (r['lng'] != null) _lng.text = (r['lng'] as num).toString();
      }
    } catch (_) {
      // 初期取得失敗は新規作成として扱う
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await supabase.rpc('upsert_my_restaurant', params: {
        'p_name': _name.text.trim(),
        'p_description': _description.text.trim(),
        'p_address': _address.text.trim(),
        'p_lat': double.parse(_lat.text.trim()),
        'p_lng': double.parse(_lng.text.trim()),
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
      appBar: AppBar(title: const Text('店舗情報')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: '店名', border: OutlineInputBorder()),
                      validator: _required,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: '紹介文', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(
                          labelText: '住所', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _lat,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: '緯度(lat)',
                                border: OutlineInputBorder()),
                            validator: _number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lng,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: '経度(lng)',
                                border: OutlineInputBorder()),
                            validator: _number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '※ 会津若松駅周辺が初期値です。地図から指定する機能は今後対応。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
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
                          : const Text('保存する'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? '入力してください' : null;

  String? _number(String? v) =>
      (v == null || double.tryParse(v.trim()) == null) ? '数値を入力' : null;
}
