-- Таблица просмотров и функция increment_post_view (если ещё не созданы)
-- Выполните в Supabase SQL Editor

CREATE TABLE IF NOT EXISTS post_views (
  post_id UUID PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
  view_count BIGINT NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION increment_post_view(p_post_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO post_views (post_id, view_count) VALUES (p_post_id, 1)
  ON CONFLICT (post_id) DO UPDATE SET view_count = post_views.view_count + 1;
END;
$$;

GRANT EXECUTE ON FUNCTION increment_post_view(UUID) TO anon;
GRANT EXECUTE ON FUNCTION increment_post_view(UUID) TO authenticated;
