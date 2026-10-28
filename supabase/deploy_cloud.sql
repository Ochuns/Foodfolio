-- ==============================================================
-- Foodfolio 本番(クラウド)適用SQL
-- Supabase SQL Editor に全部貼り付けて Run してください。
-- （PostGIS/pgcrypto を extensions スキーマに用意してから適用）
-- ==============================================================
create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;
set search_path = public, extensions;

-- =============================================================
-- Foodfolio 初期スキーマ
--   - エンティティ: profiles / restaurants / menu_items /
--     groups / group_items / coupons / cards / user_coupons
--   - PostGIS で「近くの辞典導入店」検索
--   - カード作成時にグループ達成を判定しクーポンを自動発行
--   - RLS で「公開は誰でも閲覧／編集は所有者のみ」を担保
-- 実行: Supabase SQL Editor に貼り付け or `supabase db push`
-- =============================================================

-- -------------------------------------------------------------
-- 0. 拡張機能
-- -------------------------------------------------------------
create extension if not exists postgis;    -- 地理空間検索 (geography 型 / ST_*)
create extension if not exists pgcrypto;    -- gen_random_uuid() / gen_random_bytes()

-- -------------------------------------------------------------
-- 共通: updated_at 自動更新トリガー関数
-- -------------------------------------------------------------
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =============================================================
-- 1. profiles  (auth.users を拡張するユーザープロフィール)
-- =============================================================
create table profiles (
  id          uuid primary key references auth.users on delete cascade,
  display_name text,
  avatar_url  text,
  -- 'user' = 一般(学生) / 'owner' = 飲食店オーナー / 'admin'
  role        text not null default 'user' check (role in ('user','owner','admin')),
  created_at  timestamptz not null default now()
);

-- サインアップ時に profiles 行を自動作成（role も metadata から保存）
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
    case when new.raw_user_meta_data->>'role' = 'owner' then 'owner' else 'user' end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- =============================================================
-- 2. restaurants  (飲食店。辞典の持ち主)
-- =============================================================
create table restaurants (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references auth.users on delete cascade,
  name              text not null,
  description       text,
  address           text,
  -- 緯度経度。PostGIS geography(Point) は (経度, 緯度) の順で格納する点に注意
  location          geography(Point, 4326),
  phone             text,
  image_url         text,
  -- 登録の仮条件: 会津コイン導入
  aizu_coin_enabled boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
-- 近傍検索を高速化する空間インデックス
create index restaurants_location_gix on restaurants using gist (location);
create index restaurants_owner_idx     on restaurants (owner_id);

create trigger restaurants_set_updated_at
  before update on restaurants
  for each row execute function set_updated_at();

-- =============================================================
-- 3. menu_items  (メニュー = 辞典の構成要素)
-- =============================================================
create table menu_items (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants on delete cascade,
  name          text not null,
  description   text,
  price         integer,          -- 円
  image_url     text,
  category      text,             -- 例: ラーメン / サイドメニュー
  sort_order    integer not null default 0,
  is_published  boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index menu_items_restaurant_idx on menu_items (restaurant_id);

create trigger menu_items_set_updated_at
  before update on menu_items
  for each row execute function set_updated_at();

-- =============================================================
-- 4. groups  (メニューの括り。クーポン達成条件の単位)
--    例: 「塩ラーメングループ」「当店のおすすめ」
-- =============================================================
create table groups (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references restaurants on delete cascade,
  name          text not null,
  description   text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index groups_restaurant_idx on groups (restaurant_id);

create trigger groups_set_updated_at
  before update on groups
  for each row execute function set_updated_at();

-- =============================================================
-- 5. group_items  (group ↔ menu_item の多対多)
--    「このグループを構成するメニュー」
-- =============================================================
create table group_items (
  group_id     uuid not null references groups on delete cascade,
  menu_item_id uuid not null references menu_items on delete cascade,
  primary key (group_id, menu_item_id)
);
create index group_items_menu_item_idx on group_items (menu_item_id);

-- =============================================================
-- 6. coupons  (グループ達成時に発行される特典テンプレート)
--    1グループ1クーポン (unique)。必要なら制約を外して複数可に。
-- =============================================================
create table coupons (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null unique references groups on delete cascade,
  title            text not null,
  description      text,
  -- 'amount'=円引き / 'percent'=%引き / 'freebie'=無料提供 / 'coin'=会津コイン還元
  discount_type    text not null default 'amount'
                     check (discount_type in ('amount','percent','freebie','coin')),
  discount_value   integer,
  aizu_coin_amount integer,          -- 会津コイン還元額 (discount_type='coin' 等で使用)
  valid_days       integer default 30, -- 発行後の有効日数 (null=無期限)
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create trigger coupons_set_updated_at
  before update on coupons
  for each row execute function set_updated_at();

-- =============================================================
-- 7. cards  (ユーザー × メニュー の「食べた記録」= 辞典を埋める)
--    1ユーザー1メニューにつき1枚 (collection セマンティクス)
-- =============================================================
create table cards (
  id            uuid primary key default gen_random_uuid(),
  -- default auth.uid(): ログイン中ユーザーのIDを自動補完（クライアントは送らなくてよい）
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  menu_item_id  uuid not null references menu_items on delete cascade,
  restaurant_id uuid references restaurants on delete cascade, -- 検索用に非正規化 (下のトリガーで自動補完)
  memo          text,
  rating        smallint check (rating between 1 and 5),
  photo_url     text,
  created_at    timestamptz not null default now(),
  unique (user_id, menu_item_id)
);
create index cards_user_idx      on cards (user_id);
create index cards_menu_item_idx on cards (menu_item_id);

-- restaurant_id を menu_item から自動補完 (整合性担保)
create or replace function set_card_restaurant()
returns trigger language plpgsql as $$
begin
  if new.restaurant_id is null then
    select restaurant_id into new.restaurant_id from menu_items where id = new.menu_item_id;
  end if;
  return new;
end;
$$;

create trigger cards_set_restaurant
  before insert on cards
  for each row execute function set_card_restaurant();

-- =============================================================
-- 8. user_coupons  (ユーザーに実際に発行されたクーポン)
-- =============================================================
create table user_coupons (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  coupon_id  uuid not null references coupons on delete cascade,
  group_id   uuid references groups on delete cascade, -- 検索用に非正規化
  status     text not null default 'issued' check (status in ('issued','used','expired')),
  code       text not null,          -- QR / コード表示用トークン
  issued_at  timestamptz not null default now(),
  used_at    timestamptz,
  expires_at timestamptz,
  unique (user_id, coupon_id)        -- 同一クーポンは1回のみ発行
);
create index user_coupons_user_idx on user_coupons (user_id);

-- =============================================================
-- 9. クーポン自動発行ロジック
--    カード作成後、そのメニューを含む各グループについて
--    「全メニューが揃ったか」を判定し、揃えばクーポンを発行する
-- =============================================================
create or replace function issue_coupons_on_card()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  g record;
begin
  for g in
    select group_id from group_items where menu_item_id = new.menu_item_id
  loop
    -- グループ内に「未カード化のメニュー」が1つも無ければ達成
    if not exists (
      select 1
      from group_items gi
      where gi.group_id = g.group_id
        and not exists (
          select 1 from cards c
          where c.user_id = new.user_id
            and c.menu_item_id = gi.menu_item_id
        )
    ) then
      insert into user_coupons (user_id, coupon_id, group_id, code, expires_at)
      select new.user_id,
             cp.id,
             g.group_id,
             -- コア関数 gen_random_uuid() でトークン生成（pgcrypto 非依存で堅牢）
             replace(gen_random_uuid()::text, '-', ''),
             case when cp.valid_days is not null
                  then now() + (cp.valid_days || ' days')::interval
                  else null end
      from coupons cp
      where cp.group_id = g.group_id and cp.is_active = true
      on conflict (user_id, coupon_id) do nothing;  -- 既発行はスキップ
    end if;
  end loop;
  return new;
end;
$$;

create trigger cards_issue_coupons
  after insert on cards
  for each row execute function issue_coupons_on_card();

-- =============================================================
-- 10. 近傍の飲食店検索 (マップ用 RPC)
--     client からは supabase.rpc('nearby_restaurants', {...}) で呼ぶ
-- =============================================================
create or replace function nearby_restaurants(
  lat       double precision,
  lng       double precision,
  radius_m  integer default 2000
)
returns table (
  id          uuid,
  name        text,
  address     text,
  image_url   text,
  lat_out     double precision,
  lng_out     double precision,
  distance_m  double precision
)
language sql stable
set search_path = public, extensions as $$
  select r.id, r.name, r.address, r.image_url,
         ST_Y(r.location::geometry) as lat_out,
         ST_X(r.location::geometry) as lng_out,
         ST_Distance(r.location, ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography) as distance_m
  from restaurants r
  where r.location is not null
    and ST_DWithin(r.location, ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography, radius_m)
  order by distance_m;
$$;

-- =============================================================
-- 11. 所有者判定ヘルパー (RLS で使用)
-- =============================================================
create or replace function is_restaurant_owner(r_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from restaurants where id = r_id and owner_id = auth.uid());
$$;

create or replace function is_group_owner(g_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from groups g
    join restaurants r on r.id = g.restaurant_id
    where g.id = g_id and r.owner_id = auth.uid()
  );
$$;

-- =============================================================
-- 12. RLS 有効化
-- =============================================================
alter table profiles     enable row level security;
alter table restaurants  enable row level security;
alter table menu_items   enable row level security;
alter table groups       enable row level security;
alter table group_items  enable row level security;
alter table coupons      enable row level security;
alter table cards        enable row level security;
alter table user_coupons enable row level security;

-- ---- profiles: 公開閲覧 / 本人のみ編集 ----
create policy profiles_select on profiles for select using (true);
create policy profiles_insert on profiles for insert with check (auth.uid() = id);
create policy profiles_update on profiles for update using (auth.uid() = id);

-- ---- restaurants: 公開閲覧 / 所有者のみ編集 ----
create policy restaurants_select on restaurants for select using (true);
create policy restaurants_insert on restaurants for insert with check (auth.uid() = owner_id);
create policy restaurants_update on restaurants for update using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy restaurants_delete on restaurants for delete using (auth.uid() = owner_id);

-- ---- menu_items: 公開閲覧 / 店舗所有者のみ編集 ----
create policy menu_items_select on menu_items for select using (true);
create policy menu_items_write  on menu_items for all
  using (is_restaurant_owner(restaurant_id))
  with check (is_restaurant_owner(restaurant_id));

-- ---- groups: 公開閲覧 / 店舗所有者のみ編集 ----
create policy groups_select on groups for select using (true);
create policy groups_write  on groups for all
  using (is_restaurant_owner(restaurant_id))
  with check (is_restaurant_owner(restaurant_id));

-- ---- group_items: 公開閲覧 / グループ所有者のみ編集 ----
create policy group_items_select on group_items for select using (true);
create policy group_items_write  on group_items for all
  using (is_group_owner(group_id))
  with check (is_group_owner(group_id));

-- ---- coupons: 公開閲覧 / グループ所有者のみ編集 ----
create policy coupons_select on coupons for select using (true);
create policy coupons_write  on coupons for all
  using (is_group_owner(group_id))
  with check (is_group_owner(group_id));

-- ---- cards: 本人のみ CRUD ----
create policy cards_select on cards for select using (auth.uid() = user_id);
create policy cards_insert on cards for insert with check (auth.uid() = user_id);
create policy cards_update on cards for update using (auth.uid() = user_id);
create policy cards_delete on cards for delete using (auth.uid() = user_id);

-- ---- user_coupons: 本人のみ閲覧 / 使用済み更新 ----
--   発行は SECURITY DEFINER トリガーが行う (RLS をバイパス) ため insert ポリシーは不要
create policy user_coupons_select on user_coupons for select using (auth.uid() = user_id);
create policy user_coupons_update on user_coupons for update using (auth.uid() = user_id);

-- =============================================================
-- 13. Storage バケット (メニュー写真 / カード写真)
-- =============================================================
insert into storage.buckets (id, name, public) values
  ('menu-images', 'menu-images', true),
  ('card-photos', 'card-photos', true)
on conflict (id) do nothing;

-- 公開読み取り
create policy "public read menu-images" on storage.objects
  for select using (bucket_id = 'menu-images');
create policy "public read card-photos" on storage.objects
  for select using (bucket_id = 'card-photos');

-- menu-images: 認証ユーザーがアップロード (店舗オーナー運用を想定)
create policy "auth write menu-images" on storage.objects
  for insert to authenticated with check (bucket_id = 'menu-images');
create policy "auth update menu-images" on storage.objects
  for update to authenticated using (bucket_id = 'menu-images');
create policy "auth delete menu-images" on storage.objects
  for delete to authenticated using (bucket_id = 'menu-images');

-- card-photos: 本人フォルダ (先頭パス = uid) のみ操作可
create policy "auth write own card-photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'card-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "auth update own card-photos" on storage.objects
  for update to authenticated
  using (bucket_id = 'card-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "auth delete own card-photos" on storage.objects
  for delete to authenticated
  using (bucket_id = 'card-photos' and (storage.foldername(name))[1] = auth.uid()::text);


-- =============================================================
-- 0002: 店舗オーナー向け RPC
--   restaurants.location (PostGIS geography) は REST から直接入れにくいため、
--   lat/lng を受け取って ST_MakePoint で生成する RPC を用意する。
--   いずれも security invoker なので既存の RLS がそのまま効く。
--   （MVP: 1オーナー1店舗を想定）
-- =============================================================

-- 自分の店舗を作成 or 更新する
create or replace function upsert_my_restaurant(
  p_name        text,
  p_description text,
  p_address     text,
  p_lat         double precision,
  p_lng         double precision
) returns uuid
language plpgsql
security invoker
set search_path = public, extensions as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select id into v_id from restaurants where owner_id = auth.uid() limit 1;

  if v_id is null then
    insert into restaurants (owner_id, name, description, address, location)
    values (
      auth.uid(), p_name, p_description, p_address,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    )
    returning id into v_id;
  else
    update restaurants
       set name        = p_name,
           description = p_description,
           address     = p_address,
           location    = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
     where id = v_id;
  end if;

  return v_id;
end;
$$;

-- 自分の店舗を lat/lng 付きで取得する（フォームの初期表示用）
create or replace function get_my_restaurant()
returns table (
  id          uuid,
  name        text,
  description text,
  address     text,
  lat         double precision,
  lng         double precision
)
language sql
stable
security invoker
set search_path = public, extensions as $$
  select r.id, r.name, r.description, r.address,
         ST_Y(r.location::geometry) as lat,
         ST_X(r.location::geometry) as lng
  from restaurants r
  where r.owner_id = auth.uid()
  limit 1;
$$;
