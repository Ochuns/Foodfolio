// Foodfolio の最小スモークテスト。
// ウィジェットテストは Supabase 初期化を伴うため、ここでは軽量な sanity check のみ。
// 画面単位のテストは各 feature 配下で追加していく。

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanity check', () {
    expect(1 + 1, 2);
  });
}
