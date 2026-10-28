-- =============================================================
-- 来店ジオフェンス判定RPC
--   - 指定座標が、ある店舗の位置から radius_m メートル以内かを返す。
--   - チェキ作成を「実際に来店しているとき」に限定するために使う。
--   - 距離計算は PostGIS(ST_DWithin / geography) でサーバー側実施。
--   - 位置未登録(location is null)の店舗は判定不能のため true（ブロックしない）。
-- client からは supabase.rpc('is_within_restaurant', {...}) で呼ぶ。
-- =============================================================
create or replace function is_within_restaurant(
  r_id     uuid,
  lat      double precision,
  lng      double precision,
  radius_m integer default 30
)
returns boolean
language sql stable
set search_path = public, extensions as $$
  select coalesce(
    bool_or(
      r.location is null
      or ST_DWithin(
           r.location,
           ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
           radius_m
         )
    ),
    false  -- 店舗が見つからなければ false（作成不可）
  )
  from restaurants r
  where r.id = r_id;
$$;
