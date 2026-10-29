-- =============================================================
-- グループの手動セット化 ＋ クーポン繰り返し獲得 ＋ チェキ使用済み印
--   - これまで「カード作成時にグループ達成を自動判定してクーポン発行」だったが、
--     ユーザーが自分のチェキを各メニュー枠に手動でセットして獲得する方式に変更する。
--   - クーポンは一度きりにせず、獲得するたびにグループ枠はリセット（再挑戦可能）。
--   - 獲得に使ったチェキは used_at で「使用済み」印が残り、再利用できない。
-- =============================================================

-- -------------------------------------------------------------
-- 1) チェキの使用済み印（クーポン獲得に使うと刻印される。永続）
-- -------------------------------------------------------------
alter table cards add column if not exists used_at timestamptz;

-- -------------------------------------------------------------
-- 2) 自動発行をやめる（トリガーと関数を撤去）
-- -------------------------------------------------------------
drop trigger if exists cards_issue_coupons on cards;
drop function if exists issue_coupons_on_card();

-- -------------------------------------------------------------
-- 3) クーポンを繰り返し獲得できるように（1ユーザー1クーポンの制限を解除）
-- -------------------------------------------------------------
alter table user_coupons drop constraint if exists user_coupons_user_id_coupon_id_key;

-- -------------------------------------------------------------
-- 4) グループ枠へのチェキ手動セット
--    (user, group, menu_item) ごとに、自分のチェキを1枚割り当てる
-- -------------------------------------------------------------
create table if not exists group_selections (
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  group_id     uuid not null references groups on delete cascade,
  menu_item_id uuid not null references menu_items on delete cascade,
  card_id      uuid not null references cards on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (user_id, group_id, menu_item_id)
);
create index if not exists group_selections_card_idx on group_selections(card_id);

alter table group_selections enable row level security;
drop policy if exists group_selections_select on group_selections;
drop policy if exists group_selections_write  on group_selections;
create policy group_selections_select on group_selections
  for select using (auth.uid() = user_id);
create policy group_selections_write on group_selections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- -------------------------------------------------------------
-- 5) RPC: メニュー枠にチェキをセット（自分の・該当メニュー・未使用のみ）
-- -------------------------------------------------------------
create or replace function set_group_selection(
  p_group_id uuid, p_menu_item_id uuid, p_card_id uuid
)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if not exists (
    select 1 from cards
    where id = p_card_id and user_id = auth.uid()
      and menu_item_id = p_menu_item_id and used_at is null
  ) then
    raise exception '対象のチェキが無効か、使用済みです';
  end if;
  if not exists (
    select 1 from group_items
    where group_id = p_group_id and menu_item_id = p_menu_item_id
  ) then
    raise exception 'このメニューはグループに含まれていません';
  end if;
  insert into group_selections (user_id, group_id, menu_item_id, card_id)
  values (auth.uid(), p_group_id, p_menu_item_id, p_card_id)
  on conflict (user_id, group_id, menu_item_id)
  do update set card_id = excluded.card_id, created_at = now();
end $$;

-- -------------------------------------------------------------
-- 6) RPC: メニュー枠のセット解除
-- -------------------------------------------------------------
create or replace function clear_group_selection(
  p_group_id uuid, p_menu_item_id uuid
)
returns void language sql security invoker set search_path = public as $$
  delete from group_selections
  where user_id = auth.uid()
    and group_id = p_group_id
    and menu_item_id = p_menu_item_id;
$$;

-- -------------------------------------------------------------
-- 7) RPC: クーポン獲得
--    全メニュー枠が埋まっていれば発行 → 使用チェキに刻印 → 枠をリセット
--    （security definer: user_coupons への発行と cards の刻印を行うため）
-- -------------------------------------------------------------
create or replace function claim_group_coupon(p_group_id uuid)
returns table (out_coupon_id uuid, out_code text)
language plpgsql security definer set search_path = public as $$
declare
  v_coupon   coupons;
  v_total    int;
  v_filled   int;
  v_code     text;
  v_expires  timestamptz;
begin
  select * into v_coupon from coupons
   where group_id = p_group_id and is_active = true
   limit 1;
  if not found then
    raise exception 'このグループに有効なクーポンがありません';
  end if;

  select count(*) into v_total from group_items where group_id = p_group_id;
  if v_total = 0 then
    raise exception 'グループにメニューがありません';
  end if;

  -- 埋まっている枠数（セット済みかつ、そのカードが未使用）
  select count(*) into v_filled
  from group_items gi
  join group_selections gs
    on gs.group_id = gi.group_id
   and gs.menu_item_id = gi.menu_item_id
   and gs.user_id = auth.uid()
  join cards c on c.id = gs.card_id and c.used_at is null
  where gi.group_id = p_group_id;

  if v_filled < v_total then
    raise exception 'まだ全てのメニューにチェキがセットされていません';
  end if;

  v_code := replace(gen_random_uuid()::text, '-', '');
  v_expires := case when v_coupon.valid_days is not null
                    then now() + (v_coupon.valid_days || ' days')::interval
                    else null end;

  insert into user_coupons (user_id, coupon_id, group_id, code, expires_at)
  values (auth.uid(), v_coupon.id, p_group_id, v_code, v_expires);

  -- 使用したチェキに「使用済み」印
  update cards set used_at = now()
   where id in (
     select card_id from group_selections
     where user_id = auth.uid() and group_id = p_group_id
   );

  -- グループ枠をリセット（再挑戦可能に）
  delete from group_selections
   where user_id = auth.uid() and group_id = p_group_id;

  out_coupon_id := v_coupon.id;
  out_code := v_code;
  return next;
end $$;
