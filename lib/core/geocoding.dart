import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// 住所検索の1件分の結果。
class GeocodeResult {
  const GeocodeResult({
    required this.displayName,
    required this.position,
  });

  /// 表示用の住所文字列
  final String displayName;

  /// 緯度経度
  final LatLng position;
}

/// OpenStreetMap ベースの住所⇔座標変換（Photon / komoot）。
///
/// - APIキー不要・無料。既存のOSM地図タイルと相性が良い。
/// - Nominatim と違い、公式エンドポイントが実レスポンスで CORS ヘッダ
///   (Access-Control-Allow-Origin: *) を返すため、**Flutter Web からも使える**。
/// - 公開インスタンスのためフェアユース前提（ハッカソン用途の低頻度利用）。
class Geocoding {
  static const _host = 'photon.komoot.io';

  /// 住所・施設名から候補地点を検索する（前方ジオコーディング）。
  /// 失敗時は空リストを返す（例外を投げない）。
  static Future<List<GeocodeResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    // lang=default: 地名を現地語（日本語）で返す
    final uri = Uri.https(_host, '/api', {
      'q': q,
      'limit': '5',
      'lang': 'default',
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final features = (body['features'] as List?) ?? const [];
      return features
          .map((f) => _toResult(f as Map<String, dynamic>))
          .whereType<GeocodeResult>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 座標から住所文字列を取得する（逆ジオコーディング）。
  /// 失敗時は null を返す（例外を投げない）。
  static Future<String?> reverse(LatLng pos) async {
    final uri = Uri.https(_host, '/reverse', {
      'lat': pos.latitude.toString(),
      'lon': pos.longitude.toString(),
      'lang': 'default',
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final features = (body['features'] as List?) ?? const [];
      if (features.isEmpty) return null;
      final props = (features.first as Map<String, dynamic>)['properties']
          as Map<String, dynamic>?;
      final addr = props == null ? null : _composeAddress(props);
      return (addr == null || addr.isEmpty) ? null : addr;
    } catch (_) {
      return null;
    }
  }

  /// Photon の GeoJSON Feature を GeocodeResult へ変換。
  static GeocodeResult? _toResult(Map<String, dynamic> feature) {
    final geom = feature['geometry'] as Map<String, dynamic>?;
    final coords = geom?['coordinates'] as List?;
    if (coords == null || coords.length < 2) return null;
    // GeoJSON は [経度, 緯度] の順
    final lon = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    final props = feature['properties'] as Map<String, dynamic>? ?? const {};
    return GeocodeResult(
      displayName: _composeAddress(props),
      position: LatLng(lat, lon),
    );
  }

  /// Photon の構造化プロパティから「福島県会津若松市栄町…」のような住所を組み立てる。
  /// 大きい行政区画 → 小さい単位 の順に、重複を除いて連結する。
  static String _composeAddress(Map<String, dynamic> props) {
    const order = [
      'state', // 都道府県
      'county', // 郡
      'city', // 市区町村
      'district', // 地区
      'suburb',
      'neighbourhood',
      'quarter',
      'street', // 通り
      'housenumber', // 番地
      'name', // 施設名など
    ];
    final seen = <String>{};
    final parts = <String>[];
    for (final key in order) {
      final v = props[key]?.toString().trim();
      if (v != null && v.isNotEmpty && seen.add(v)) {
        parts.add(v);
      }
    }
    final postcode = props['postcode']?.toString().trim();
    final body = parts.join('');
    if (postcode != null && postcode.isNotEmpty) {
      return '〒$postcode $body';
    }
    return body;
  }
}
