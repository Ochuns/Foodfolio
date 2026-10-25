-- =============================================================
-- Foodfolio デモ用シードデータ
--   前提: 先に1人サインアップしておくこと (最初のユーザーをオーナーに使う)
--   実行: Supabase SQL Editor に貼り付け or `supabase db reset` で自動適用
-- =============================================================
do $$
declare
  v_owner       uuid;
  v_restaurant  uuid;
  v_shio1       uuid;
  v_shio2       uuid;
  v_shio3       uuid;
  v_gyoza       uuid;
  v_group       uuid;
begin
  -- 最初の auth ユーザーをオーナーとして採用
  select id into v_owner from auth.users order by created_at limit 1;
  if v_owner is null then
    raise notice 'auth.users が空です。先にサインアップしてから再実行してください。';
    return;
  end if;

  update profiles set role = 'owner' where id = v_owner;

  -- 店舗 (会津若松駅付近の座標)
  insert into restaurants (owner_id, name, description, address, location, aizu_coin_enabled)
  values (
    v_owner,
    '会津ラーメン 喜楽',
    '会津の地元に愛される昔ながらの中華そば店。',
    '福島県会津若松市中町1-1',
    ST_SetSRID(ST_MakePoint(139.9296, 37.4948), 4326)::geography,  -- (経度, 緯度)
    true
  )
  returning id into v_restaurant;

  -- メニュー (辞典の中身)
  insert into menu_items (restaurant_id, name, price, category, sort_order)
    values (v_restaurant, '塩ラーメン',       780, 'ラーメン', 1) returning id into v_shio1;
  insert into menu_items (restaurant_id, name, price, category, sort_order)
    values (v_restaurant, '特製塩ラーメン',   980, 'ラーメン', 2) returning id into v_shio2;
  insert into menu_items (restaurant_id, name, price, category, sort_order)
    values (v_restaurant, 'ネギ塩ラーメン',   880, 'ラーメン', 3) returning id into v_shio3;
  insert into menu_items (restaurant_id, name, price, category, sort_order)
    values (v_restaurant, '餃子',             450, 'サイド',   4) returning id into v_gyoza;

  -- グループ (塩ラーメン全種)
  insert into groups (restaurant_id, name, description)
  values (v_restaurant, '塩ラーメングループ', '当店の塩ラーメン3種を制覇しよう！')
  returning id into v_group;

  insert into group_items (group_id, menu_item_id) values
    (v_group, v_shio1),
    (v_group, v_shio2),
    (v_group, v_shio3);

  -- クーポン (グループ達成時に発行)
  insert into coupons (group_id, title, description, discount_type, discount_value, valid_days)
  values (v_group, '塩ラーメン制覇クーポン', '次回会計から200円引き（会津コイン対応）', 'amount', 200, 30);

  raise notice 'シード完了: restaurant=%  owner=%', v_restaurant, v_owner;
end;
$$;
