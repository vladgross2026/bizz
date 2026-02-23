-- Админ-чат: пользователи пишут администрации, админ видит и отвечает
-- Выполните в Supabase SQL Editor

-- 1. Функция: создать/получить admin-диалог для пользователя
CREATE OR REPLACE FUNCTION create_or_get_admin_conversation(p_user_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cid UUID;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Только владелец может создавать свой admin-диалог';
  END IF;
  SELECT c.id INTO v_cid
  FROM conversations c
  JOIN conversation_participants cp ON cp.conversation_id = c.id
  WHERE c.type = 'admin' AND cp.user_id = p_user_id
  LIMIT 1;
  IF v_cid IS NOT NULL THEN
    RETURN v_cid;
  END IF;
  INSERT INTO conversations (type) VALUES ('admin') RETURNING id INTO v_cid;
  INSERT INTO conversation_participants (conversation_id, user_id)
  VALUES (v_cid, p_user_id);
  RETURN v_cid;
END;
$$;
GRANT EXECUTE ON FUNCTION create_or_get_admin_conversation(UUID) TO authenticated;

-- 2. Функция: список admin-диалогов для админа (с превью последнего сообщения)
CREATE OR REPLACE FUNCTION get_admin_conversations_list()
RETURNS TABLE(
  conversation_id UUID,
  user_id UUID,
  user_name TEXT,
  last_body TEXT,
  last_created_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    c.id AS conversation_id,
    cp.user_id AS user_id,
    TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')) AS user_name,
    m.body AS last_body,
    m.created_at AS last_created_at
  FROM conversations c
  JOIN conversation_participants cp ON cp.conversation_id = c.id
  LEFT JOIN profiles p ON p.id = cp.user_id
  LEFT JOIN LATERAL (
    SELECT body, created_at FROM messages
    WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1
  ) m ON true
  WHERE c.type = 'admin'
  ORDER BY m.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_admin_conversations_list() TO authenticated;

-- 3. Функция: админ отправляет сообщение
CREATE OR REPLACE FUNCTION admin_send_message(p_conv_id UUID, p_body TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_msg_id UUID;
BEGIN
  IF NOT is_admin() OR p_body IS NULL OR trim(p_body) = '' THEN
    RAISE EXCEPTION 'Доступ запрещён';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conv_id AND type = 'admin') THEN
    RAISE EXCEPTION 'Диалог не найден';
  END IF;
  INSERT INTO messages (conversation_id, sender_id, body)
  VALUES (p_conv_id, auth.uid(), trim(p_body))
  RETURNING id INTO v_msg_id;
  RETURN v_msg_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_send_message(UUID, TEXT) TO authenticated;

-- 4. Функция: админ читает сообщения (обходит RLS)
CREATE OR REPLACE FUNCTION admin_get_messages(p_conv_id UUID)
RETURNS TABLE(msg_id UUID, sender_id UUID, body TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conv_id AND type = 'admin') THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT m.id, m.sender_id, m.body, m.created_at
  FROM messages m
  WHERE m.conversation_id = p_conv_id
  ORDER BY m.created_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_get_messages(UUID) TO authenticated;
