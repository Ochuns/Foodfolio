import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';

/// 辞典導入店マップ。
/// 現在地を取得して周辺の辞典導入店を検索する（近傍検索は PostGIS の RPC が担当）。
/// 現在地が取れない / 周辺に店が無い場合は会津若松での検索にフォールバックできる。
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // 羊皮紙調のテーマカラー
  static const _parchment = Color(0xFFF0E4C8);
  static const _parchmentBar = Color(0xFFEFE6CF);

  /// タイルの彩度を 65% に落とす色マトリクス（Rec.709 輝度）。
  /// これにクリーム色の乗算を重ねて「古地図/羊皮紙」調にする。
  static const List<double> _desaturate = [
    0.724, 0.250, 0.025, 0, 0, //
    0.074, 0.900, 0.025, 0, 0, //
    0.074, 0.250, 0.675, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  /// 会津若松駅周辺（フォールバックの中心）
  static const _aizu = LatLng(37.4948, 139.9296);
  static const double _radiusNear = 5000; // 現在地周辺の検索半径(m)
  static const double _radiusAizu = 100000; // 会津全体を見るための広い半径(m)

  final _mapController = MapController();

  LatLng? _currentLocation;
  List<Marker> _restaurantMarkers = [];
  bool _loading = true;
  String? _error;
  bool _noResults = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final pos = await _getCurrentPosition();
    final center = pos != null ? LatLng(pos.latitude, pos.longitude) : _aizu;
    if (pos != null) _currentLocation = center;
    await _search(center, pos != null ? _radiusNear : _radiusAizu);
    _safeMove(center, pos != null ? 14 : 12);
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

  Future<void> _search(LatLng center, double radiusM) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await supabase.rpc('nearby_restaurants', params: {
        'lat': center.latitude,
        'lng': center.longitude,
        'radius_m': radiusM.toInt(),
      }) as List;

      if (!mounted) return;
      setState(() {
        _restaurantMarkers = rows.map((row) {
          final r = row as Map<String, dynamic>;
          final id = r['id'] as String;
          final name = r['name'] as String? ?? '';
          final address = r['address'] as String? ?? '';
          return Marker(
            point: LatLng(
              (r['lat_out'] as num).toDouble(),
              (r['lng_out'] as num).toDouble(),
            ),
            width: 46,
            height: 54,
            // ピンの「先端（下）」を座標に合わせる
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () => _showRestaurantSheet(id, name, address),
              child: const _RestaurantPin(),
            ),
          );
        }).toList();
        _noResults = rows.isEmpty;
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

  void _safeMove(LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {
      // マップ未構築時は無視（initialCenter が使われる）
    }
  }

  Future<void> _goToCurrent() async {
    final pos = await _getCurrentPosition();
    if (pos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('現在地を取得できませんでした（位置情報の許可を確認してください）'),
        ));
      }
      return;
    }
    final center = LatLng(pos.latitude, pos.longitude);
    setState(() => _currentLocation = center);
    await _search(center, _radiusNear);
    _safeMove(center, 14);
  }

  Future<void> _goToAizu() async {
    await _search(_aizu, _radiusAizu);
    _safeMove(_aizu, 12);
  }

  /// ピンをタップしたときの店舗情報シート。辞典詳細への導線を出す。
  void _showRestaurantSheet(String id, String name, String address) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(sheetContext).textTheme.titleLarge),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(address),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    context.push('/restaurant/$id');
                  },
                  icon: const Icon(Icons.menu_book),
                  label: const Text('辞典を見る'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Marker> get _allMarkers {
    final markers = [..._restaurantMarkers];
    final loc = _currentLocation;
    if (loc != null) {
      markers.add(
        Marker(
          point: loc,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2E7DF6),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _parchment,
      appBar: AppBar(
        title: const Text('辞典導入店マップ'),
        actions: [
          IconButton(
            tooltip: '会津若松で探す',
            icon: const Icon(Icons.search),
            onPressed: _goToAizu,
          ),
          const AccountButton(),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _aizu,
              initialZoom: 12,
              backgroundColor: _parchment,
            ),
            children: [
              TileLayer(
                // キー不要の OpenStreetMap 標準タイル（CORS(*) 対応）。
                // 本番では利用規約・レート制限に配慮した提供元を検討する。
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.foodfolio.foodfolio',
                // 彩度を落として → クリーム色を乗算し、古地図/羊皮紙調に。
                tileBuilder: (context, tileWidget, tile) => ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                      Color(0xFFF2E8CE), BlendMode.multiply),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(_desaturate),
                    child: tileWidget,
                  ),
                ),
              ),
              MarkerLayer(markers: _allMarkers),
            ],
          ),
          // 右下の方位磁石（タップで現在地へ）
          Positioned(
            right: 16,
            bottom: 16,
            child: Tooltip(
              message: '現在地へ',
              child: GestureDetector(
                onTap: _goToCurrent,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _parchmentBar,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFB8860B), width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 5,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: const Icon(Icons.explore,
                      color: Color(0xFFB8860B), size: 30),
                ),
              ),
            ),
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _noResults)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Expanded(child: Text('近くに辞典導入店がありません。')),
                      TextButton(
                        onPressed: _goToAizu,
                        child: const Text('会津若松で探す'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Material(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '店舗の取得に失敗しました:\n$_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 辞典導入店を示すオレンジのティアドロップ型ピン。
/// 中央に金色の円＋フォーク＆ナイフ（辞典テーマの飲食店マーク）。
class _RestaurantPin extends StatelessWidget {
  const _RestaurantPin();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 46,
      height: 54,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // ティアドロップ本体（やわらかい影つき）
          Icon(
            Icons.location_on,
            size: 50,
            color: Color(0xFFD2521E),
            shadows: [
              Shadow(
                  color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          // 中央のエンブレム（金の円＋フォーク＆ナイフ）
          Positioned(
            top: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFE8C87A),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 26,
                height: 26,
                child: Icon(Icons.restaurant,
                    size: 15, color: Color(0xFF8A3B12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
