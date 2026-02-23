-- Удаление из друзей: политика DELETE и функция friends_remove
-- Выполните в Supabase SQL Editor

DROP POLICY IF EXISTS "friend_requests_delete" ON friend_requests;
CREATE POLICY "friend_requests_delete" ON friend_requests
  FOR DELETE USING (
    status = 'accepted' AND (from_user_id = auth.uid() OR to_user_id = auth.uid())
  );

CREATE OR REPLACE FUNCTION friends_remove(p_friend_user_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Не авторизован';
  END IF;
  DELETE FROM friend_requests
  WHERE status = 'accepted'
    AND ((from_user_id = v_uid AND to_user_id = p_friend_user_id)
      OR (from_user_id = p_friend_user_id AND to_user_id = v_uid));
END;
$$;
GRANT EXECUTE ON FUNCTION friends_remove(UUID) TO authenticated;
