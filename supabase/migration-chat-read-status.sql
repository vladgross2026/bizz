-- Отслеживание прочитанных сообщений в чатах
-- Выполните в Supabase SQL Editor

-- Таблица: когда пользователь последний раз "прочитал" чат (открыл или просмотрел)
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

-- Обновить get_dm_conversations_with_preview: добавить колонку unread_count
CREATE OR REPLACE FUNCTION get_dm_conversations_with_preview()
RETURNS TABLE (
  conversation_id UUID,
  other_user_id UUID,
  other_name TEXT,
  last_body TEXT,
  last_created_at TIMESTAMPTZ,
  unread_count BIGINT
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
  WITH my_dms AS (
    SELECT cp.conversation_id
    FROM conversation_participants cp
    JOIN conversations c ON c.id = cp.conversation_id
    WHERE cp.user_id = v_uid AND c.type = 'dm'
  ),
  other_participant AS (
    SELECT cp.conversation_id, cp.user_id AS other_id
    FROM conversation_participants cp
    JOIN my_dms m ON m.conversation_id = cp.conversation_id
    WHERE cp.user_id != v_uid
  ),
  last_msg AS (
    SELECT DISTINCT ON (m.conversation_id)
      m.conversation_id, m.body, m.created_at
    FROM messages m
    JOIN my_dms d ON d.conversation_id = m.conversation_id
    ORDER BY m.conversation_id, m.created_at DESC
  ),
  unread AS (
    SELECT m.conversation_id, COUNT(*)::BIGINT AS cnt
    FROM messages m
    JOIN my_dms d ON d.conversation_id = m.conversation_id
    LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = v_uid
    WHERE m.sender_id != v_uid
      AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at)
    GROUP BY m.conversation_id
  )
  SELECT
    op.conversation_id,
    op.other_id,
    COALESCE(TRIM(p.first_name || ' ' || p.last_name), p.company, '—') AS name,
    lm.body,
    lm.created_at,
    COALESCE(u.cnt, 0)::BIGINT
  FROM other_participant op
  LEFT JOIN last_msg lm ON lm.conversation_id = op.conversation_id
  LEFT JOIN profiles p ON p.id = op.other_id
  LEFT JOIN unread u ON u.conversation_id = op.conversation_id
  ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_dm_conversations_with_preview() TO authenticated;

-- Отметить чат как прочитанный
CREATE OR REPLACE FUNCTION mark_conversation_read(p_conversation_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  INSERT INTO conversation_last_read (user_id, conversation_id, last_read_at)
  VALUES (v_uid, p_conversation_id, now())
  ON CONFLICT (user_id, conversation_id) DO UPDATE SET last_read_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION mark_conversation_read(UUID) TO authenticated;

-- Общее количество непрочитанных сообщений по всем DM и групповым чатам пользователя
CREATE OR REPLACE FUNCTION get_total_unread_chat_count()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_total BIGINT := 0;
BEGIN
  IF v_uid IS NULL THEN RETURN 0; END IF;
  SELECT COUNT(*)::BIGINT INTO v_total
  FROM messages m
  JOIN conversation_participants cp ON cp.conversation_id = m.conversation_id AND cp.user_id = v_uid
  LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = v_uid
  WHERE m.sender_id != v_uid
    AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at);
  RETURN v_total;
END;
$$;
GRANT EXECUTE ON FUNCTION get_total_unread_chat_count() TO authenticated;

-- Расширить get_group_conversations_with_preview: добавить unread_count
CREATE OR REPLACE FUNCTION get_group_conversations_with_preview()
RETURNS TABLE (
  conversation_id UUID,
  title TEXT,
  created_by UUID,
  last_body TEXT,
  last_created_at TIMESTAMPTZ,
  unread_count BIGINT
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  RETURN QUERY
  WITH my_groups AS (
    SELECT cp.conversation_id
    FROM conversation_participants cp
    JOIN conversations c ON c.id = cp.conversation_id
    WHERE cp.user_id = v_uid AND c.type = 'group'
  ),
  last_msg AS (
    SELECT DISTINCT ON (m.conversation_id) m.conversation_id, m.body, m.created_at
    FROM messages m
    JOIN my_groups g ON g.conversation_id = m.conversation_id
    ORDER BY m.conversation_id, m.created_at DESC
  ),
  unread AS (
    SELECT m.conversation_id, COUNT(*)::BIGINT AS cnt
    FROM messages m
    JOIN my_groups g ON g.conversation_id = m.conversation_id
    LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = v_uid
    WHERE m.sender_id != v_uid
      AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at)
    GROUP BY m.conversation_id
  )
  SELECT c.id, c.title, c.created_by, lm.body, lm.created_at, COALESCE(u.cnt, 0)::BIGINT
  FROM conversations c
  JOIN my_groups g ON g.conversation_id = c.id
  LEFT JOIN last_msg lm ON lm.conversation_id = c.id
  LEFT JOIN unread u ON u.conversation_id = c.id
  ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_group_conversations_with_preview() TO authenticated;
