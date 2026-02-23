-- Объединение дубликатов DM: одна беседа на пару пользователей
-- Выполните в Supabase SQL Editor ОДИН РАЗ для очистки существующих дублей

DO $$
DECLARE
  r RECORD;
  v_keep UUID;
  v_drop UUID;
  i INT;
BEGIN
  FOR r IN (
    WITH dm_pairs AS (
      SELECT c.id, c.created_at,
        (SELECT user_id FROM conversation_participants WHERE conversation_id = c.id ORDER BY user_id::text ASC LIMIT 1) AS u1,
        (SELECT user_id FROM conversation_participants WHERE conversation_id = c.id ORDER BY user_id::text DESC LIMIT 1) AS u2
      FROM conversations c
      WHERE c.type = 'dm'
        AND (SELECT COUNT(*) FROM conversation_participants WHERE conversation_id = c.id) = 2
    ),
    dupes AS (
      SELECT u1, u2, array_agg(id ORDER BY created_at ASC) AS cids
      FROM dm_pairs
      GROUP BY u1, u2
      HAVING COUNT(*) > 1
    )
    SELECT cids FROM dupes
  ) LOOP
    v_keep := r.cids[1];
    FOR i IN 2..array_length(r.cids, 1) LOOP
      v_drop := r.cids[i];
      UPDATE messages SET conversation_id = v_keep WHERE conversation_id = v_drop;
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'conversation_last_read') THEN
        DELETE FROM conversation_last_read WHERE conversation_id = v_drop;
      END IF;
      DELETE FROM conversation_participants WHERE conversation_id = v_drop;
      DELETE FROM conversations WHERE id = v_drop;
    END LOOP;
  END LOOP;
END $$;
