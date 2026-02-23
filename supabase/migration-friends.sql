-- Знакомства: заявки в друзья и поиск профилей
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run (если таблица friend_requests ещё не создана)

CREATE TABLE IF NOT EXISTS friend_requests (
  from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (from_user_id, to_user_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_from ON friend_requests(from_user_id);

ALTER TABLE friend_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "friend_requests_select" ON friend_requests;
DROP POLICY IF EXISTS "friend_requests_insert" ON friend_requests;
DROP POLICY IF EXISTS "friend_requests_update" ON friend_requests;
CREATE POLICY "friend_requests_select" ON friend_requests FOR SELECT USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);
CREATE POLICY "friend_requests_insert" ON friend_requests FOR INSERT WITH CHECK (auth.uid() = from_user_id);
CREATE POLICY "friend_requests_update" ON friend_requests FOR UPDATE USING (auth.uid() = to_user_id);

CREATE OR REPLACE FUNCTION search_profiles_for_friends(p_query TEXT)
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, company TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT pr.id, pr.first_name, pr.last_name, pr.company
  FROM profiles pr
  WHERE pr.id != auth.uid()
    AND pr.verified = true
    AND (p_query IS NULL OR trim(p_query) = '' OR pr.first_name ILIKE '%' || trim(p_query) || '%' OR pr.last_name ILIKE '%' || trim(p_query) || '%')
  ORDER BY pr.first_name, pr.last_name
  LIMIT 30;
END;
$$;
GRANT EXECUTE ON FUNCTION search_profiles_for_friends(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION get_profiles_public(p_ids UUID[])
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, company TEXT) LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$
  SELECT pr.id, pr.first_name, pr.last_name, pr.company FROM profiles pr WHERE pr.id = ANY(p_ids);
$$;
GRANT EXECUTE ON FUNCTION get_profiles_public(UUID[]) TO authenticated;
