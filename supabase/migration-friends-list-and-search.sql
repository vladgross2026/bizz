-- Список людей для знакомств (по алфавиту, с пагинацией) и поиск по всем профилям
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run

-- Поиск и список: только верифицированные пользователи (добавить в друзья можно только их)
CREATE OR REPLACE FUNCTION search_profiles_for_friends(p_query TEXT)
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, company TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT pr.id, pr.first_name, pr.last_name, pr.company
  FROM profiles pr
  WHERE pr.id != auth.uid()
    AND pr.verified = true
    AND (p_query IS NULL OR trim(p_query) = '' OR pr.first_name ILIKE '%' || trim(p_query) || '%' OR pr.last_name ILIKE '%' || trim(p_query) || '%' OR pr.company ILIKE '%' || trim(p_query) || '%')
  ORDER BY lower(pr.first_name), lower(pr.last_name)
  LIMIT 100;
END;
$$;
GRANT EXECUTE ON FUNCTION search_profiles_for_friends(TEXT) TO authenticated;

-- Список профилей (только верифицированные) с пагинацией и счётчиками
CREATE OR REPLACE FUNCTION list_profiles_for_friends(p_limit INT, p_offset INT)
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, company TEXT, posts_count BIGINT, total_views BIGINT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT pr.id, pr.first_name, pr.last_name, pr.company,
    (SELECT count(*)::BIGINT FROM posts WHERE posts.author_id = pr.id AND posts.status = 'published'),
    (SELECT coalesce(sum(pv.view_count), 0)::BIGINT FROM posts p JOIN post_views pv ON p.id = pv.post_id WHERE p.author_id = pr.id)
  FROM profiles pr
  WHERE pr.id != auth.uid()
    AND pr.verified = true
  ORDER BY lower(pr.first_name), lower(pr.last_name)
  LIMIT greatest(1, least(100, p_limit))
  OFFSET greatest(0, p_offset);
END;
$$;
GRANT EXECUTE ON FUNCTION list_profiles_for_friends(INT, INT) TO authenticated;
