import 'package:flutter/foundation.dart';

/// 環境ごとの挙動フラグ。
///
/// テスト（`flutter run` のデバッグビルド）では開発しやすさを優先し、
/// 本番（`flutter build web --release`）では仕様どおり厳格にする。
/// `kReleaseMode` は release ビルドで true、debug/profile で false。
class AppConfig {
  AppConfig._();

  /// 来店ジオフェンスを強制するか。
  /// - 本番: true（店舗の近くにいないとチェキを作成できない）
  /// - テスト: false（現地に行けないため判定をスキップ）
  /// ※ ジオフェンスだけ試したいときは一時的に true に書き換える。
  static const bool enforceVisitLocation = kReleaseMode;

  /// 来店とみなす半径（メートル）。
  static const int visitRadiusM = 30;

  /// 写真をカメラ撮影のみに限定するか（添付を禁止するか）。
  /// - 本番: true（その場で撮影）
  /// - テスト: false（カメラ／ギャラリー添付のどちらも可）
  static const bool cameraOnly = kReleaseMode;
}
