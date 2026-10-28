import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geocoding.dart';
import '../../core/supabase.dart';

/// 店舗の登録 / 編集フォーム。
/// 位置は地図をタップして指定し、住所は Nominatim で自動入力できる。
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
  final _search = TextEditingController();

  final _mapController = MapController();
  // 会津若松駅周辺を初期値に
  LatLng _picked = const LatLng(37.4948, 139.9296);

  List<GeocodeResult> _results = [];
  bool _searching = false;
  bool _reversing = false;

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
        if (r['lat'] != null && r['lng'] != null) {
          _picked = LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
        }
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
    _search.dispose();
    super.dispose();
  }

  void _safeMove(LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {
      // マップ未構築時は無視
    }
  }

  /// ピン位置を更新する。[reverse] が true なら住所を逆引きして自動入力。
  Future<void> _setPicked(LatLng pos, {bool reverse = false, double? zoom}) async {
    setState(() => _picked = pos);
    _safeMove(pos, zoom ?? _mapController.camera.zoom);
    if (!reverse) return;
    setState(() => _reversing = true);
    final addr = await Geocoding.reverse(pos);
    if (!mounted) return;
    setState(() {
      if (addr != null) _address.text = addr;
      _reversing = false;
    });
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _results = [];
    });
    final results = await Geocoding.search(q);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('該当する場所が見つかりませんでした')),
      );
    }
  }

  void _selectResult(GeocodeResult r) {
    setState(() {
      _address.text = r.displayName;
      _results = [];
      _search.clear();
    });
    _setPicked(r.position, zoom: 17);
  }

  Future<void> _useCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw '位置情報サービスが無効です';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw '位置情報の利用が許可されていません';
      }
      final pos = await Geolocator.getCurrentPosition();
      await _setPicked(LatLng(pos.latitude, pos.longitude),
          reverse: true, zoom: 17);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('現在地を取得できませんでした（$e）')),
      );
    }
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
        'p_lat': _picked.latitude,
        'p_lng': _picked.longitude,
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
                    const SizedBox(height: 24),
                    Text('場所', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text(
                      '住所で検索するか、地図をタップして場所を指定してください。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    // --- 住所検索 ---
                    TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(),
                      decoration: InputDecoration(
                        labelText: '住所・店名で検索',
                        hintText: '例: 会津若松市 栄町',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : IconButton(
                                icon: const Icon(Icons.arrow_forward),
                                onPressed: _runSearch,
                              ),
                      ),
                    ),
                    // --- 検索結果 ---
                    if (_results.isNotEmpty)
                      Card(
                        margin: const EdgeInsets.only(top: 4),
                        child: Column(
                          children: [
                            for (final r in _results)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.place_outlined),
                                title: Text(r.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                onTap: () => _selectResult(r),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    // --- 地図（タップで位置指定） ---
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 280,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _picked,
                                initialZoom: 16,
                                onTap: (_, latlng) =>
                                    _setPicked(latlng, reverse: true),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.foodfolio.foodfolio',
                                ),
                                MarkerLayer(markers: [
                                  Marker(
                                    point: _picked,
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.bottomCenter,
                                    child: const Icon(Icons.location_on,
                                        color: Colors.red, size: 40),
                                  ),
                                ]),
                              ],
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: FloatingActionButton.small(
                                heroTag: 'current_loc',
                                tooltip: '現在地を使う',
                                onPressed: _useCurrentLocation,
                                child: const Icon(Icons.my_location),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // --- 住所（自動入力・手動修正可） ---
                    TextFormField(
                      controller: _address,
                      decoration: InputDecoration(
                        labelText: '住所',
                        border: const OutlineInputBorder(),
                        helperText: '地図から自動入力されます（手動修正も可能）',
                        suffixIcon: _reversing
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '緯度 ${_picked.latitude.toStringAsFixed(6)} / '
                      '経度 ${_picked.longitude.toStringAsFixed(6)}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
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
}
