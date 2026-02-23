-- GROSS:форум — полная миграция для Supabase
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run
-- Можно запускать повторно (идемпотентно)

-- ========== 1. Реакции на комментариях и лучший ответ ==========
CREATE TABLE IF NOT EXISTS comment_reactions (
  comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha','useful')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_comment_reactions_comment ON comment_reactions(comment_id);
ALTER TABLE comment_reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "comment_reactions_select" ON comment_reactions;
CREATE POLICY "comment_reactions_select" ON comment_reactions FOR SELECT USING (true);
DROP POLICY IF EXISTS "comment_reactions_insert" ON comment_reactions;
CREATE POLICY "comment_reactions_insert" ON comment_reactions FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "comment_reactions_delete" ON comment_reactions;
CREATE POLICY "comment_reactions_delete" ON comment_reactions FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE comment_reactions DROP CONSTRAINT IF EXISTS comment_reactions_type_check;
ALTER TABLE comment_reactions ADD CONSTRAINT comment_reactions_type_check
  CHECK (type IN ('muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha','useful'));

ALTER TABLE posts ADD COLUMN IF NOT EXISTS best_answer_comment_id UUID REFERENCES comments(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_posts_best_answer ON posts(best_answer_comment_id) WHERE best_answer_comment_id IS NOT NULL;

-- ========== 2. Репутация и бейджи ==========
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS company_stage TEXT
  CHECK (company_stage IS NULL OR company_stage IN ('idea','startup_1_3','startup_3_5','growth','enterprise','other'));

CREATE TABLE IF NOT EXISTS badges (
  id TEXT PRIMARY KEY,
  name_ru TEXT NOT NULL,
  description_ru TEXT,
  icon TEXT,
  rule_type TEXT NOT NULL DEFAULT 'computed' CHECK (rule_type IN ('computed','assigned'))
);
INSERT INTO badges (id, name_ru, description_ru, rule_type) VALUES
  ('helped_10', 'Помог 10 раз', '10+ полезных ответов', 'computed'),
  ('helped_50', 'Помог 50 раз', '50+ полезных ответов', 'computed'),
  ('helped_100', 'Помог 100 раз', '100+ полезных ответов', 'computed'),
  ('startup_1_3', 'Стартап 1–3 года', 'Компания на этапе 1–3 года', 'computed'),
  ('startup_3_5', 'Стартап 3–5 лет', 'Компания на этапе 3–5 лет', 'computed'),
  ('expert_marketing', 'Эксперт по маркетингу', 'Активность в категории Маркетинг', 'computed'),
  ('expert_finance', 'Эксперт по финансам', 'Активность в категории Финансы', 'computed'),
  ('expert_sales', 'Эксперт по продажам', 'Активность в категории Продажи', 'computed')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS user_badges (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_id TEXT NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, badge_id)
);
CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "user_badges_select" ON user_badges;
CREATE POLICY "user_badges_select" ON user_badges FOR SELECT USING (true);
DROP POLICY IF EXISTS "user_badges_insert" ON user_badges;
CREATE POLICY "user_badges_insert" ON user_badges FOR INSERT WITH CHECK (is_admin());
DROP POLICY IF EXISTS "user_badges_delete" ON user_badges;
CREATE POLICY "user_badges_delete" ON user_badges FOR DELETE USING (is_admin());

-- ========== 3. Админ: лучший ответ ==========
CREATE OR REPLACE FUNCTION admin_set_best_answer(p_post_id UUID, p_comment_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  UPDATE posts SET best_answer_comment_id = p_comment_id WHERE id = p_post_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_set_best_answer(UUID, UUID) TO authenticated;

-- ========== 4. Функция: бейджи пользователя ==========
CREATE OR REPLACE FUNCTION get_user_badges(p_user_id UUID)
RETURNS TABLE(badge_id TEXT, name_ru TEXT, description_ru TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE helpful_cnt BIGINT;
DECLARE stage TEXT;
BEGIN
  SELECT pr.company_stage INTO stage FROM profiles pr WHERE pr.id = p_user_id;
  SELECT COUNT(DISTINCT cr.comment_id) INTO helpful_cnt FROM comments c
    JOIN comment_reactions cr ON cr.comment_id = c.id AND cr.type = 'useful'
    WHERE c.author_id = p_user_id;
  RETURN QUERY SELECT ub.badge_id, b.name_ru, b.description_ru FROM user_badges ub JOIN badges b ON b.id = ub.badge_id WHERE ub.user_id = p_user_id;
  IF helpful_cnt >= 100 THEN RETURN QUERY SELECT 'helped_100'::TEXT, 'Помог 100 раз'::TEXT, '100+ полезных ответов'::TEXT; END IF;
  IF helpful_cnt >= 50 THEN RETURN QUERY SELECT 'helped_50'::TEXT, 'Помог 50 раз'::TEXT, '50+ полезных ответов'::TEXT; END IF;
  IF helpful_cnt >= 10 THEN RETURN QUERY SELECT 'helped_10'::TEXT, 'Помог 10 раз'::TEXT, '10+ полезных ответов'::TEXT; END IF;
  IF stage = 'startup_1_3' THEN RETURN QUERY SELECT 'startup_1_3'::TEXT, 'Стартап 1–3 года'::TEXT, 'Компания на этапе 1–3 года'::TEXT; END IF;
  IF stage = 'startup_3_5' THEN RETURN QUERY SELECT 'startup_3_5'::TEXT, 'Стартап 3–5 лет'::TEXT, 'Компания на этапе 3–5 лет'::TEXT; END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION get_user_badges(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_badges(UUID) TO anon;

-- ========== 5. admin_update_profile с company_stage ==========
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_update_profile(p_id UUID, p_first_name TEXT, p_last_name TEXT, p_company TEXT, p_verified BOOLEAN, p_company_stage TEXT DEFAULT NULL)
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
    updated_at = now()
  WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT) TO authenticated;

-- ========== 6. Категории: Полезное и Ищу партнерства ==========
INSERT INTO categories (id, name, slug) VALUES
  ('useful', 'Полезное', 'useful'),
  ('partnership', 'Ищу партнерства', 'partnership'),
  ('everyday', 'Житейское', 'everyday')
ON CONFLICT (id) DO NOTHING;

-- ========== 7. Realtime для messages ==========
-- Для мгновенной доставки DM: выполните migration-chat-realtime.sql (один раз)

-- ========== 8. Админ-чат: пользователи пишут администрации, админ отвечает ==========
CREATE OR REPLACE FUNCTION create_or_get_admin_conversation(p_user_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cid UUID;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN RAISE EXCEPTION 'Только владелец может создавать свой admin-диалог'; END IF;
  SELECT c.id INTO v_cid FROM conversations c JOIN conversation_participants cp ON cp.conversation_id = c.id WHERE c.type = 'admin' AND cp.user_id = p_user_id LIMIT 1;
  IF v_cid IS NOT NULL THEN RETURN v_cid; END IF;
  INSERT INTO conversations (type) VALUES ('admin') RETURNING id INTO v_cid;
  INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, p_user_id);
  RETURN v_cid;
END;
$$;
GRANT EXECUTE ON FUNCTION create_or_get_admin_conversation(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION get_admin_conversations_list()
RETURNS TABLE(conversation_id UUID, user_id UUID, user_name TEXT, last_body TEXT, last_created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  RETURN QUERY
  SELECT c.id, cp.user_id, TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,''))::TEXT, m.body, m.created_at
  FROM conversations c JOIN conversation_participants cp ON cp.conversation_id = c.id
  LEFT JOIN profiles p ON p.id = cp.user_id
  LEFT JOIN LATERAL (SELECT body, created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) m ON true
  WHERE c.type = 'admin' ORDER BY m.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_admin_conversations_list() TO authenticated;

CREATE OR REPLACE FUNCTION admin_send_message(p_conv_id UUID, p_body TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_msg_id UUID;
BEGIN
  IF NOT is_admin() OR p_body IS NULL OR trim(p_body) = '' THEN RAISE EXCEPTION 'Доступ запрещён'; END IF;
  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conv_id AND type = 'admin') THEN RAISE EXCEPTION 'Диалог не найден'; END IF;
  INSERT INTO messages (conversation_id, sender_id, body) VALUES (p_conv_id, auth.uid(), trim(p_body)) RETURNING id INTO v_msg_id;
  RETURN v_msg_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_send_message(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION admin_get_messages(p_conv_id UUID)
RETURNS TABLE(msg_id UUID, sender_id UUID, body TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conv_id AND type = 'admin') THEN RETURN; END IF;
  RETURN QUERY SELECT m.id, m.sender_id, m.body, m.created_at FROM messages m WHERE m.conversation_id = p_conv_id ORDER BY m.created_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_get_messages(UUID) TO authenticated;

-- ========== 9. Прочитанные сообщения в чатах (unread badges) ==========
CREATE TABLE IF NOT EXISTS conversation_last_read (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, conversation_id)
);
CREATE INDEX IF NOT EXISTS idx_conversation_last_read_user ON conversation_last_read(user_id);
ALTER TABLE conversation_last_read ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conversation_last_read_select" ON conversation_last_read;
CREATE POLICY "conversation_last_read_select" ON conversation_last_read FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "conversation_last_read_insert" ON conversation_last_read;
CREATE POLICY "conversation_last_read_insert" ON conversation_last_read FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "conversation_last_read_update" ON conversation_last_read;
CREATE POLICY "conversation_last_read_update" ON conversation_last_read FOR UPDATE USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION get_dm_conversations_with_preview()
RETURNS TABLE (conversation_id UUID, other_user_id UUID, other_name TEXT, last_body TEXT, last_created_at TIMESTAMPTZ, unread_count BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  RETURN QUERY
  WITH my_dms AS (SELECT cp.conversation_id FROM conversation_participants cp JOIN conversations c ON c.id = cp.conversation_id WHERE cp.user_id = v_uid AND c.type = 'dm'),
  other_participant AS (SELECT cp.conversation_id, cp.user_id AS other_id FROM conversation_participants cp JOIN my_dms m ON m.conversation_id = cp.conversation_id WHERE cp.user_id != v_uid),
  last_msg AS (SELECT DISTINCT ON (m.conversation_id) m.conversation_id, m.body, m.created_at FROM messages m JOIN my_dms d ON d.conversation_id = m.conversation_id ORDER BY m.conversation_id, m.created_at DESC),
  unread AS (SELECT m.conversation_id, COUNT(*)::BIGINT AS cnt FROM messages m JOIN my_dms d ON d.conversation_id = m.conversation_id LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = v_uid WHERE m.sender_id != v_uid AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at) GROUP BY m.conversation_id)
  SELECT op.conversation_id, op.other_id, COALESCE(TRIM(p.first_name || ' ' || p.last_name), p.company, '—')::TEXT, lm.body, lm.created_at, COALESCE(u.cnt, 0)::BIGINT
  FROM other_participant op LEFT JOIN last_msg lm ON lm.conversation_id = op.conversation_id LEFT JOIN profiles p ON p.id = op.other_id LEFT JOIN unread u ON u.conversation_id = op.conversation_id
  ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_dm_conversations_with_preview() TO authenticated;

CREATE OR REPLACE FUNCTION mark_conversation_read(p_conversation_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN IF auth.uid() IS NULL THEN RETURN; END IF; INSERT INTO conversation_last_read (user_id, conversation_id, last_read_at) VALUES (auth.uid(), p_conversation_id, now()) ON CONFLICT (user_id, conversation_id) DO UPDATE SET last_read_at = now(); END;
$$;
GRANT EXECUTE ON FUNCTION mark_conversation_read(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION get_total_unread_chat_count()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_total BIGINT := 0;
BEGIN
  IF auth.uid() IS NULL THEN RETURN 0; END IF;
  SELECT COUNT(*)::BIGINT INTO v_total FROM messages m
  JOIN conversation_participants cp ON cp.conversation_id = m.conversation_id AND cp.user_id = auth.uid()
  LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = auth.uid()
  WHERE m.sender_id != auth.uid() AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at);
  RETURN v_total;
END;
$$;
GRANT EXECUTE ON FUNCTION get_total_unread_chat_count() TO authenticated;

-- get_group_conversations_with_preview with unread_count (требует migration-chat-groups)
CREATE OR REPLACE FUNCTION get_group_conversations_with_preview()
RETURNS TABLE (conversation_id UUID, title TEXT, created_by UUID, last_body TEXT, last_created_at TIMESTAMPTZ, unread_count BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  RETURN QUERY
  WITH my_groups AS (SELECT cp.conversation_id FROM conversation_participants cp JOIN conversations c ON c.id = cp.conversation_id WHERE cp.user_id = v_uid AND c.type = 'group'),
  last_msg AS (SELECT DISTINCT ON (m.conversation_id) m.conversation_id, m.body, m.created_at FROM messages m JOIN my_groups g ON g.conversation_id = m.conversation_id ORDER BY m.conversation_id, m.created_at DESC),
  unread AS (SELECT m.conversation_id, COUNT(*)::BIGINT AS cnt FROM messages m JOIN my_groups g ON g.conversation_id = m.conversation_id LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = v_uid WHERE m.sender_id != v_uid AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at) GROUP BY m.conversation_id)
  SELECT c.id, c.title, c.created_by, lm.body, lm.created_at, COALESCE(u.cnt, 0)::BIGINT
  FROM conversations c JOIN my_groups g ON g.conversation_id = c.id LEFT JOIN last_msg lm ON lm.conversation_id = c.id LEFT JOIN unread u ON u.conversation_id = c.id
  ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_group_conversations_with_preview() TO authenticated;
