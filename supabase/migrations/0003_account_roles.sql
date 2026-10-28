-- =============================================================
-- アカウント種別（role）をサインアップ時に保存する
--   - 一般ユーザー(user) / 飲食店オーナー(owner) を登録時に選べるようにする
--   - クライアントは signUp 時の metadata に role を入れて送る
--     （raw_user_meta_data->>'role'）
--   - profiles.role カラム自体は 0001_init.sql で定義済み
-- 実行: `supabase db push` もしくは Supabase SQL Editor に貼り付け
-- =============================================================

create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
    -- 不正な値が来ても 'user' に丸める（owner のみ許可）
    case when new.raw_user_meta_data->>'role' = 'owner' then 'owner' else 'user' end
  );
  return new;
end;
$$;

-- 既存アカウントを飲食店オーナーに昇格させたい場合は、SQL Editor で以下を実行:
--   update profiles set role = 'owner' where id = '<対象ユーザーのUUID>';
