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
  static const int visitRadiusM = 2000;

  /// 来店半径の表示用ラベル（1km以上かつ端数なしは km 表記）。
  static String get visitRadiusLabel =>
      visitRadiusM >= 1000 && visitRadiusM % 1000 == 0
          ? '${visitRadiusM ~/ 1000}km'
          : '${visitRadiusM}m';

  /// 「同じ店舗では1日1枚」制限を強制するか。
  /// - お祭り運用のため全環境で false（1日に何枚でも作成可）。
  /// ※ 本番クラウドDBの一意インデックス cards_one_per_day_per_restaurant も
  ///   併せて DROP する必要がある（残っていると 23505 でブロックされる）。
  static const bool enforceDailyLimit = false;

  /// 写真をカメラ撮影のみに限定するか（添付を禁止するか）。
  /// - 本番: true（その場で撮影）
  /// - テスト: false（カメラ／ギャラリー添付のどちらも可）
  static const bool cameraOnly = kReleaseMode;
}
