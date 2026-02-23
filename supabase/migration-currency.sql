-- Внутрисайтовая валюта и платные посты (категория «Полезное»)
-- Выполните в Supabase SQL Editor

-- 1. Баланс в профилях
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS balance INTEGER NOT NULL DEFAULT 0;

-- 2. Цена поста (только для category_id = 'useful')
ALTER TABLE posts ADD COLUMN IF NOT EXISTS price INTEGER;
ALTER TABLE posts ADD CONSTRAINT posts_price_non_negative CHECK (price IS NULL OR price >= 0);

-- 3. Покупки постов
CREATE TABLE IF NOT EXISTS post_purchases (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_post_purchases_user ON post_purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_post_purchases_post ON post_purchases(post_id);
ALTER TABLE post_purchases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "post_purchases_select" ON post_purchases;
CREATE POLICY "post_purchases_select" ON post_purchases FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "post_purchases_insert" ON post_purchases;
CREATE POLICY "post_purchases_insert" ON post_purchases FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 4. Покупка платного поста
CREATE OR REPLACE FUNCTION buy_post(p_post_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_price INTEGER;
  v_author_id UUID;
  v_buyer_bal INTEGER;
  v_author_bal INTEGER;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
  SELECT p.price, p.author_id INTO v_price, v_author_id
  FROM posts p WHERE p.id = p_post_id AND p.status = 'published';
  IF v_price IS NULL OR v_price <= 0 THEN RAISE EXCEPTION 'Пост не платный'; END IF;
  IF v_author_id = v_uid THEN RAISE EXCEPTION 'Нельзя купить свой пост'; END IF;
  IF EXISTS (SELECT 1 FROM post_purchases WHERE user_id = v_uid AND post_id = p_post_id) THEN
    RAISE EXCEPTION 'Вы уже купили этот пост'; END IF;
  SELECT COALESCE(balance, 0) INTO v_buyer_bal FROM profiles WHERE id = v_uid;
  IF v_buyer_bal < v_price THEN RAISE EXCEPTION 'Недостаточно средств'; END IF;
  SELECT COALESCE(balance, 0) INTO v_author_bal FROM profiles WHERE id = v_author_id;
  UPDATE profiles SET balance = balance - v_price, updated_at = now() WHERE id = v_uid;
  UPDATE profiles SET balance = balance + v_price, updated_at = now() WHERE id = v_author_id;
  INSERT INTO post_purchases (user_id, post_id, amount) VALUES (v_uid, p_post_id, v_price);
END;
$$;
GRANT EXECUTE ON FUNCTION buy_post(UUID) TO authenticated;

-- 5. Админ добавляет баланс
CREATE OR REPLACE FUNCTION admin_add_balance(p_user_id UUID, p_amount INTEGER)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Доступ запрещён'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Сумма должна быть положительной'; END IF;
  UPDATE profiles SET balance = COALESCE(balance, 0) + p_amount, updated_at = now() WHERE id = p_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_add_balance(UUID, INTEGER) TO authenticated;

-- 6. admin_update_profile: добавить p_balance (админ может устанавливать баланс)
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT);
CREATE OR REPLACE FUNCTION admin_update_profile(p_id UUID, p_first_name TEXT, p_last_name TEXT, p_company TEXT, p_verified BOOLEAN, p_company_stage TEXT DEFAULT NULL, p_balance INTEGER DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  UPDATE profiles SET
    first_name = COALESCE(p_first_name, first_name),
    last_name = COALESCE(p_last_name, last_name),
    company = COALESCE(p_company, company),
    verified = COALESCE(p_verified, verified),
    company_stage = COALESCE(p_company_stage, company_stage),
    balance = CASE WHEN p_balance IS NOT NULL THEN p_balance ELSE balance END,
    updated_at = now()
  WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER) TO authenticated;

-- Если admin_list_profiles не возвращает balance, добавьте в его SELECT:
-- SELECT ..., p.balance, ... FROM profiles p ...

-- 7. Подсчёт подписчиков автора (RLS на subscriptions не даёт считать по author_id)
CREATE OR REPLACE FUNCTION get_subscriber_count(p_author_id UUID)
RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$ SELECT count(*)::int FROM subscriptions WHERE author_id = p_author_id; $$;
GRANT EXECUTE ON FUNCTION get_subscriber_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_subscriber_count(UUID) TO anon;
