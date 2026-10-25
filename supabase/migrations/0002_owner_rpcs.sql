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
