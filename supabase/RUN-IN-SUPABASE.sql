-- =============================================================================
-- Скопируйте весь файл в Supabase: SQL Editor → New query → вставьте → Run
-- Повторный запуск безопасен (идемпотентно)
-- =============================================================================

-- Подписка: безлимит и 2 бесплатных открытия поста в месяц
-- profiles.subscription_ends_at — до какой даты действует безлимит
-- post_opens — учёт бесплатных открытий (2 в месяц)

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS subscription_ends_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS balance INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS post_opens (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_post_opens_user_created ON post_opens(user_id, created_at);
ALTER TABLE post_opens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "post_opens_select" ON post_opens;
DROP POLICY IF EXISTS "post_opens_insert" ON post_opens;
CREATE POLICY "post_opens_select" ON post_opens FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "post_opens_insert" ON post_opens FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Получить статус подписки и оставшиеся открытия
CREATE OR REPLACE FUNCTION get_subscription_status()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE v_uid UUID := auth.uid(); v_ends TIMESTAMPTZ; v_opens INT; v_limit INT := 2;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('has_subscription', false, 'opens_remaining', 0); END IF;
  SELECT subscription_ends_at INTO v_ends FROM profiles WHERE id = v_uid;
  IF v_ends IS NOT NULL AND v_ends > now() THEN RETURN jsonb_build_object('has_subscription', true, 'opens_remaining', v_limit); END IF;
  SELECT count(*)::int INTO v_opens FROM post_opens WHERE user_id = v_uid AND created_at >= date_trunc('month', now());
  RETURN jsonb_build_object('has_subscription', false, 'opens_remaining', GREATEST(0, v_limit - v_opens));
END;
$$;
GRANT EXECUTE ON FUNCTION get_subscription_status() TO authenticated;
GRANT EXECUTE ON FUNCTION get_subscription_status() TO anon;

-- Использовать одно бесплатное открытие поста
CREATE OR REPLACE FUNCTION use_post_open(p_post_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ends TIMESTAMPTZ; v_opens INT; v_already BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
  SELECT subscription_ends_at INTO v_ends FROM profiles WHERE id = v_uid;
  IF v_ends IS NOT NULL AND v_ends > now() THEN RETURN jsonb_build_object('ok', true, 'opens_remaining', 2); END IF;
  SELECT EXISTS (SELECT 1 FROM post_opens WHERE user_id = v_uid AND post_id = p_post_id) INTO v_already;
  IF v_already THEN SELECT count(*)::int INTO v_opens FROM post_opens WHERE user_id = v_uid AND created_at >= date_trunc('month', now()); RETURN jsonb_build_object('ok', true, 'opens_remaining', GREATEST(0, 2 - v_opens)); END IF;
  SELECT count(*)::int INTO v_opens FROM post_opens WHERE user_id = v_uid AND created_at >= date_trunc('month', now());
  IF v_opens >= 2 THEN RAISE EXCEPTION 'post_opens_limit'; END IF;
  INSERT INTO post_opens (user_id, post_id) VALUES (v_uid, p_post_id) ON CONFLICT (user_id, post_id) DO NOTHING;
  RETURN jsonb_build_object('ok', true, 'opens_remaining', GREATEST(0, 2 - v_opens - 1));
END;
$$;
GRANT EXECUTE ON FUNCTION use_post_open(UUID) TO authenticated;

-- Проверить, открывал ли пользователь этот пост
CREATE OR REPLACE FUNCTION has_opened_post(p_post_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM post_opens WHERE user_id = auth.uid() AND post_id = p_post_id);
$$;
GRANT EXECUTE ON FUNCTION has_opened_post(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION has_opened_post(UUID) TO anon;

-- Список ID постов, которые пользователь уже открывал
CREATE OR REPLACE FUNCTION get_opened_post_ids()
RETURNS UUID[] LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT COALESCE(array_agg(post_id), ARRAY[]::UUID[]) FROM post_opens WHERE user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION get_opened_post_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION get_opened_post_ids() TO anon;

-- admin_update_profile: добавить subscription_ends_at
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER);
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_update_profile(p_id UUID, p_first_name TEXT, p_last_name TEXT, p_company TEXT, p_verified BOOLEAN, p_company_stage TEXT DEFAULT NULL, p_balance INTEGER DEFAULT NULL, p_subscription_ends_at TIMESTAMPTZ DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  UPDATE profiles SET
    first_name = COALESCE(p_first_name, first_name),
    last_name = COALESCE(p_last_name, last_name),
    company = COALESCE(p_company, company),
    verified = COALESCE(p_verified, verified),
    company_stage = COALESCE(p_company_stage, company_stage),
    balance = CASE WHEN p_balance IS NOT NULL THEN p_balance ELSE balance END,
    subscription_ends_at = CASE WHEN p_subscription_ends_at IS NOT NULL THEN p_subscription_ends_at ELSE subscription_ends_at END,
    updated_at = now()
  WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER, TIMESTAMPTZ) TO authenticated;

-- Подсчёт подписчиков для нескольких авторов (для рейтинга постов)
CREATE OR REPLACE FUNCTION get_subscriber_counts(p_author_ids UUID[])
RETURNS TABLE(author_id UUID, cnt BIGINT) LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT s.author_id, count(*)::BIGINT
  FROM subscriptions s
  WHERE s.author_id = ANY(p_author_ids)
  GROUP BY s.author_id;
$$;
GRANT EXECUTE ON FUNCTION get_subscriber_counts(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_subscriber_counts(UUID[]) TO anon;

-- Заглушка get_total_unread_chat_count (убирает 404). Полная версия — в migration-chat-read-status.sql
CREATE OR REPLACE FUNCTION get_total_unread_chat_count()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN 0;
END;
$$;
GRANT EXECUTE ON FUNCTION get_total_unread_chat_count() TO authenticated;
