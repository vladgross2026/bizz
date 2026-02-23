-- Если видите ошибку 404 для get_total_unread_chat_count — выполните этот SQL в Supabase.
-- Эта заглушка возвращает 0 и не требует таблиц чатов.

CREATE OR REPLACE FUNCTION get_total_unread_chat_count()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN 0;
END;
$$;
GRANT EXECUTE ON FUNCTION get_total_unread_chat_count() TO authenticated;
