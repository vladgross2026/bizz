-- RPC: список DM-диалогов с превью последнего сообщения
-- Выполните в Supabase SQL Editor

CREATE OR REPLACE FUNCTION get_dm_conversations_with_preview()
RETURNS TABLE (
  conversation_id UUID,
  other_user_id UUID,
  other_name TEXT,
  last_body TEXT,
  last_created_at TIMESTAMPTZ
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
  )
  SELECT
    op.conversation_id,
    op.other_id,
    COALESCE(TRIM(p.first_name || ' ' || p.last_name), p.company, '—') AS name,
    lm.body,
    lm.created_at
  FROM other_participant op
  LEFT JOIN last_msg lm ON lm.conversation_id = op.conversation_id
  LEFT JOIN profiles p ON p.id = op.other_id
  ORDER BY lm.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_dm_conversations_with_preview() TO authenticated;
