import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/supabase.dart';
import '../auth/account_button.dart';

/// 辞典導入店をマップ上に表示する画面。
/// 店舗の取得は Supabase の RPC `nearby_restaurants` を使う。
/// （近傍検索ロジックは PostGIS 側が担当し、ここは結果をピン表示するだけ）
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// 会津若松駅周辺（開発中の初期中心）
  static const _aizu = LatLng(37.4948, 139.9296);

  List<Marker> _markers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    try {
      final rows = await supabase.rpc('nearby_restaurants', params: {
        'lat': _aizu.latitude,
        'lng': _aizu.longitude,
        'radius_m': 50000, // 開発用に広めの半径
      }) as List<dynamic>;

      if (!mounted) return;
      setState(() {
        _markers = rows.map((row) {
          final r = row as Map<String, dynamic>;
          return Marker(
            point: LatLng(
              (r['lat_out'] as num).toDouble(),
              (r['lng_out'] as num).toDouble(),
            ),
            width: 44,
            height: 44,
            child: const Icon(Icons.restaurant, color: Colors.deepOrange, size: 36),
          );
        }).toList();
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
      appBar: AppBar(
        title: const Text('辞典導入店マップ'),
        actions: const [AccountButton()],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _aizu,
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                // 開発用。本番では利用規約を満たすタイル提供元に差し替える。
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.foodfolio.foodfolio',
              ),
              MarkerLayer(markers: _markers),
            ],
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
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
