-- Групповые чаты
-- Выполните в Supabase SQL Editor

-- Расширяем type и добавляем поля
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_type_check;
ALTER TABLE conversations ADD CONSTRAINT conversations_type_check CHECK (type IN ('dm', 'admin', 'ai', 'group'));

ALTER TABLE conversations ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Создать групповой чат (только из друзей — проверка на стороне приложения)
CREATE OR REPLACE FUNCTION create_group_chat(p_title TEXT, p_user_ids UUID[])
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_cid UUID;
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Не авторизован';
  END IF;
  IF p_title IS NULL OR TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'Укажите название чата';
  END IF;
  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL OR array_length(p_user_ids, 1) < 1 THEN
    RAISE EXCEPTION 'Добавьте хотя бы одного участника';
  END IF;
  INSERT INTO conversations (type, title, created_by) VALUES ('group', TRIM(p_title), v_uid) RETURNING id INTO v_cid;
  INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, v_uid);
  FOREACH v_id IN ARRAY p_user_ids
  LOOP
    IF v_id != v_uid THEN
      INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, v_id)
      ON CONFLICT (conversation_id, user_id) DO NOTHING;
    END IF;
  END LOOP;
  RETURN v_cid;
END;
$$;
GRANT EXECUTE ON FUNCTION create_group_chat(TEXT, UUID[]) TO authenticated;

-- Удалить участника (только создатель чата)
CREATE OR REPLACE FUNCTION remove_participant_from_group(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_created_by UUID;
  v_type TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Не авторизован';
  END IF;
  SELECT type, created_by INTO v_type, v_created_by FROM conversations WHERE id = p_conversation_id;
  IF v_type IS NULL OR v_type != 'group' THEN
    RAISE EXCEPTION 'Чат не найден или не является групповым';
  END IF;
  IF v_created_by != v_uid THEN
    RAISE EXCEPTION 'Только создатель чата может удалять участников';
  END IF;
  IF p_user_id = v_uid THEN
    RAISE EXCEPTION 'Нельзя удалить самого себя';
  END IF;
  DELETE FROM conversation_participants WHERE conversation_id = p_conversation_id AND user_id = p_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION remove_participant_from_group(UUID, UUID) TO authenticated;

-- Добавить участника в группу (только создатель)
CREATE OR REPLACE FUNCTION add_participant_to_group(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_created_by UUID;
  v_type TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Не авторизован';
  END IF;
  SELECT type, created_by INTO v_type, v_created_by FROM conversations WHERE id = p_conversation_id;
  IF v_type IS NULL OR v_type != 'group' THEN
    RAISE EXCEPTION 'Чат не найден или не является групповым';
  END IF;
  IF v_created_by != v_uid THEN
    RAISE EXCEPTION 'Только создатель чата может добавлять участников';
  END IF;
  INSERT INTO conversation_participants (conversation_id, user_id) VALUES (p_conversation_id, p_user_id)
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION add_participant_to_group(UUID, UUID) TO authenticated;

-- Список групповых чатов с превью последнего сообщения
CREATE OR REPLACE FUNCTION get_group_conversations_with_preview()
RETURNS TABLE (
  conversation_id UUID,
  title TEXT,
  created_by UUID,
  last_body TEXT,
  last_created_at TIMESTAMPTZ
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
  )
  SELECT c.id, c.title, c.created_by, lm.body, lm.created_at
  FROM conversations c
  JOIN my_groups g ON g.conversation_id = c.id
  LEFT JOIN last_msg lm ON lm.conversation_id = c.id
  ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_group_conversations_with_preview() TO authenticated;

-- Участники группового чата (для отображения и удаления)
CREATE OR REPLACE FUNCTION get_group_participants(p_conversation_id UUID)
RETURNS TABLE (user_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT cp.user_id
  FROM conversation_participants cp
  JOIN conversations c ON c.id = cp.conversation_id
  WHERE cp.conversation_id = p_conversation_id AND c.type = 'group'
  AND EXISTS (SELECT 1 FROM conversation_participants cp2 WHERE cp2.conversation_id = p_conversation_id AND cp2.user_id = auth.uid());
END;
$$;
GRANT EXECUTE ON FUNCTION get_group_participants(UUID) TO authenticated;
