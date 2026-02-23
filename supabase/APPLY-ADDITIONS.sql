-- =============================================================================
-- Дополнения SQL — скопируйте в Supabase SQL Editor и выполните
-- Идемпотентно: можно запускать повторно
-- =============================================================================

-- Колонка updated_at для комментариев (редактирование, пометка «изменено»)
ALTER TABLE comments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- Подсчёт подписчиков для нескольких авторов (рейтинг постов «Рекомендуемое»)
CREATE OR REPLACE FUNCTION get_subscriber_counts(p_author_ids UUID[])
RETURNS TABLE(author_id UUID, cnt BIGINT) LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT s.author_id, count(*)::BIGINT
  FROM subscriptions s
  WHERE s.author_id = ANY(p_author_ids)
  GROUP BY s.author_id;
$$;
GRANT EXECUTE ON FUNCTION get_subscriber_counts(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_subscriber_counts(UUID[]) TO anon;

-- Заглушка get_total_unread_chat_count (убирает 404 в чатах)
-- Полная версия — в migration-chat-read-status.sql
CREATE OR REPLACE FUNCTION get_total_unread_chat_count()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN 0;
END;
$$;
GRANT EXECUTE ON FUNCTION get_total_unread_chat_count() TO authenticated;
