-- Создание DM через функцию (обходит RLS: добавляем обоих участников)
-- ВАЖНО: сначала проверяет, нет ли уже DM между этими двумя пользователями
-- Иначе каждый видит свою беседу и сообщения не доходят
-- Выполните в Supabase SQL Editor

CREATE OR REPLACE FUNCTION create_dm_conversation(p_other_user_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_cid UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Не авторизован';
  END IF;
  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Нельзя создать чат с самим собой';
  END IF;
  -- Ищем существующий DM между этими двумя пользователями (один на пару)
  SELECT c.id INTO v_cid
  FROM conversations c
  JOIN conversation_participants cp1 ON cp1.conversation_id = c.id AND cp1.user_id = v_uid
  JOIN conversation_participants cp2 ON cp2.conversation_id = c.id AND cp2.user_id = p_other_user_id
  WHERE c.type = 'dm'
  ORDER BY c.created_at ASC
  LIMIT 1;
  IF v_cid IS NOT NULL THEN
    RETURN v_cid;
  END IF;
  -- Создаём новую беседу только если её ещё нет
  INSERT INTO conversations (type) VALUES ('dm') RETURNING id INTO v_cid;
  INSERT INTO conversation_participants (conversation_id, user_id)
  VALUES (v_cid, v_uid), (v_cid, p_other_user_id);
  RETURN v_cid;
END;
$$;
GRANT EXECUTE ON FUNCTION create_dm_conversation(UUID) TO authenticated;
