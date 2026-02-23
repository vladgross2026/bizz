-- Анонимные посты: автор не отображается, пост не показывается в профиле автора
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run

ALTER TABLE posts ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_posts_is_anonymous ON posts(is_anonymous) WHERE is_anonymous = false;

COMMENT ON COLUMN posts.is_anonymous IS 'Если true: автор не показывается (Аноним), пост не входит в список постов профиля и в счётчики.';

-- Счётчики в списке знакомств: только неанонимные посты
CREATE OR REPLACE FUNCTION list_profiles_for_friends(p_limit INT, p_offset INT)
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, company TEXT, posts_count BIGINT, total_views BIGINT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT pr.id, pr.first_name, pr.last_name, pr.company,
    (SELECT count(*)::BIGINT FROM posts WHERE posts.author_id = pr.id AND posts.status = 'published' AND (posts.is_anonymous = false OR posts.is_anonymous IS NULL)),
    (SELECT coalesce(sum(pv.view_count), 0)::BIGINT FROM posts p JOIN post_views pv ON p.id = pv.post_id WHERE p.author_id = pr.id AND (p.is_anonymous = false OR p.is_anonymous IS NULL))
  FROM profiles pr
  WHERE pr.id != auth.uid()
    AND pr.verified = true
  ORDER BY lower(pr.first_name), lower(pr.last_name)
  LIMIT greatest(1, least(100, p_limit))
  OFFSET greatest(0, p_offset);
END;
$$;
GRANT EXECUTE ON FUNCTION list_profiles_for_friends(INT, INT) TO authenticated;
