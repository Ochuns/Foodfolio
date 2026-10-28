-- =============================================================
-- 同じメニューでもチェキを複数枚持てるようにする
--   - これまで cards.unique(user_id, menu_item_id) で「1メニュー1枚」に
--     制限していたが、再撮影・複数枚コレクションを可能にするため解除する。
--   - クーポン発行ロジック(issue_coupons_on_card)は「各メニューにカードが
--     1枚以上あるか」で判定しているため、複数枚でもそのまま正しく動く。
--   - 日付はカードの created_at をそのまま利用する（追加カラム不要）。
-- 実行: `supabase db push` もしくは Supabase SQL Editor に貼り付け
-- =============================================================

-- Postgres が自動命名する一意制約名を削除（存在しなければ無視）
alter table cards drop constraint if exists cards_user_id_menu_item_id_key;
