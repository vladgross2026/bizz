-- Жалобы (reports) и чёрный список (blacklist)
-- Выполните в Supabase SQL Editor

-- Таблица жалоб
CREATE TABLE IF NOT EXISTS reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL CHECK (target_type IN ('post', 'comment')),
  target_id UUID NOT NULL,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
  admin_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports(target_type, target_id);
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "reports_insert" ON reports;
CREATE POLICY "reports_insert" ON reports FOR INSERT WITH CHECK (auth.uid() = reporter_id);
DROP POLICY IF EXISTS "reports_select_own" ON reports;
CREATE POLICY "reports_select_own" ON reports FOR SELECT USING (auth.uid() = reporter_id);

DROP POLICY IF EXISTS "reports_select_admin" ON reports;
CREATE POLICY "reports_select_admin" ON reports FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS "reports_update_admin" ON reports;
CREATE POLICY "reports_update_admin" ON reports FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());

-- Функция is_admin должна существовать
CREATE OR REPLACE FUNCTION get_reports_count()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN 0; END IF;
  RETURN (SELECT COUNT(*)::BIGINT FROM reports WHERE status = 'pending');
END;
$$;
GRANT EXECUTE ON FUNCTION get_reports_count() TO authenticated;

-- Создать жалобу
CREATE OR REPLACE FUNCTION create_report(p_target_type TEXT, p_target_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
  IF p_target_type NOT IN ('post', 'comment') THEN RAISE EXCEPTION 'Недопустимый тип'; END IF;
  INSERT INTO reports (reporter_id, target_type, target_id, reason) VALUES (auth.uid(), p_target_type, p_target_id, p_reason) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION create_report(TEXT, UUID, TEXT) TO authenticated;

-- Удаление своего аккаунта (удаляет данные, auth.users через Dashboard)
CREATE OR REPLACE FUNCTION delete_own_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
  DELETE FROM profiles WHERE id = v_uid;
  DELETE FROM favorites WHERE user_id = v_uid;
  DELETE FROM subscriptions WHERE user_id = v_uid;
  DELETE FROM user_blacklist WHERE user_id = v_uid OR blocked_user_id = v_uid;
  DELETE FROM reports WHERE reporter_id = v_uid;
  DELETE FROM friend_requests WHERE from_user_id = v_uid OR to_user_id = v_uid;
  UPDATE posts SET author_id = NULL, author_name = 'Удалённый пользователь' WHERE author_id = v_uid;
  UPDATE comments SET author_id = NULL, author_name = 'Удалённый пользователь' WHERE author_id = v_uid;
END;
$$;
GRANT EXECUTE ON FUNCTION delete_own_account() TO authenticated;

-- Чёрный список
CREATE TABLE IF NOT EXISTS user_blacklist (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, blocked_user_id),
  CHECK (user_id != blocked_user_id)
);
CREATE INDEX IF NOT EXISTS idx_user_blacklist_user ON user_blacklist(user_id);
ALTER TABLE user_blacklist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_blacklist_all" ON user_blacklist;
CREATE POLICY "user_blacklist_select" ON user_blacklist FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_blacklist_insert" ON user_blacklist FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_blacklist_delete" ON user_blacklist FOR DELETE USING (auth.uid() = user_id);
