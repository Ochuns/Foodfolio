-- =============================================================
-- 同じ店舗では「1日(JST)に1枚」までチェキを作成できるようにする
--   - 当日分のカードは「再撮影」= 同じ行の UPDATE なので、この制約に抵触しない。
--   - 判定は JST(日本時間)の暦日。式インデックスを使うため、タイムゾーンは
--     IMMUTABLE な interval 版（AT TIME ZONE interval '9:00'）で固定する。
-- 実行: `supabase db push` もしくは Supabase SQL Editor に貼り付け
-- 注意: 先に 0004（cards の per-menu 一意制約の削除）が適用されている前提。
-- =============================================================

-- 1) 既存の重複を解消（user × restaurant × JST日 ごとに最新1枚だけ残す）
--    ※ 旧ルールで同一日・同一店舗に複数メニューを集めていた場合、最新1枚に統合される。
--      発行済みの user_coupons は保持される（カード削除では取り消さない）。
delete from cards c
using cards c2
where c.user_id = c2.user_id
  and c.restaurant_id = c2.restaurant_id
  and (c.created_at  at time zone interval '9:00')::date
    = (c2.created_at at time zone interval '9:00')::date
  and (
        c.created_at < c2.created_at
        or (c.created_at = c2.created_at and c.id < c2.id)
      );

-- 2) 「店舗 × ユーザー × JST日」で一意にして、1日1枚を強制する
create unique index if not exists cards_one_per_day_per_restaurant
  on cards (
    user_id,
    restaurant_id,
    ((created_at at time zone interval '9:00')::date)
  );
