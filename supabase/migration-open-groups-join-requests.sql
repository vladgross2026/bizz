-- Open groups: description, is_open, category_id on conversations
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS is_open BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS category_id TEXT REFERENCES categories(id) ON DELETE SET NULL;

-- Join requests: user requests to join open group, creator accepts/rejects
CREATE TABLE IF NOT EXISTS group_join_requests (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_group_join_requests_conv ON group_join_requests(conversation_id);
CREATE INDEX IF NOT EXISTS idx_group_join_requests_user ON group_join_requests(user_id);
ALTER TABLE group_join_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "group_join_requests_select_creator" ON group_join_requests;
CREATE POLICY "group_join_requests_select_creator" ON group_join_requests FOR SELECT USING (
  EXISTS (SELECT 1 FROM conversations c WHERE c.id = conversation_id AND c.type = 'group' AND c.created_by = auth.uid())
);
DROP POLICY IF EXISTS "group_join_requests_select_own" ON group_join_requests;
CREATE POLICY "group_join_requests_select_own" ON group_join_requests FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "group_join_requests_insert" ON group_join_requests;
CREATE POLICY "group_join_requests_insert" ON group_join_requests FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "group_join_requests_update_creator" ON group_join_requests;
CREATE POLICY "group_join_requests_update_creator" ON group_join_requests FOR UPDATE USING (
  EXISTS (SELECT 1 FROM conversations c WHERE c.id = conversation_id AND c.type = 'group' AND c.created_by = auth.uid())
);

-- List open groups (discoverable, with optional search)
CREATE OR REPLACE FUNCTION list_open_groups(p_query TEXT DEFAULT '')
RETURNS TABLE (
  conversation_id UUID,
  title TEXT,
  description TEXT,
  category_id TEXT,
  category_name TEXT,
  created_by UUID,
  members_count BIGINT,
  my_request_status TEXT
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.title,
    c.description,
    c.category_id,
    (SELECT cat.name FROM categories cat WHERE cat.id = c.category_id LIMIT 1),
    c.created_by,
    (SELECT COUNT(*)::BIGINT FROM conversation_participants cp WHERE cp.conversation_id = c.id),
    (SELECT gjr.status FROM group_join_requests gjr WHERE gjr.conversation_id = c.id AND gjr.user_id = v_uid LIMIT 1)
  FROM conversations c
  WHERE c.type = 'group' AND c.is_open = true
    AND (p_query IS NULL OR trim(p_query) = '' OR (
      c.title ILIKE '%' || trim(p_query) || '%' OR
      (c.description IS NOT NULL AND c.description ILIKE '%' || trim(p_query) || '%')
    ))
    AND NOT EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = c.id AND cp.user_id = v_uid)
  ORDER BY c.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION list_open_groups(TEXT) TO authenticated;

-- Request to join group
CREATE OR REPLACE FUNCTION request_join_group(p_conversation_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_is_open BOOLEAN; v_type TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
  SELECT c.type, c.is_open INTO v_type, v_is_open FROM conversations c WHERE c.id = p_conversation_id;
  IF v_type IS NULL OR v_type != 'group' THEN RAISE EXCEPTION 'Группа не найдена'; END IF;
  IF NOT v_is_open THEN RAISE EXCEPTION 'Группа закрыта для вступлений'; END IF;
  IF EXISTS (SELECT 1 FROM conversation_participants WHERE conversation_id = p_conversation_id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Вы уже в группе';
  END IF;
  INSERT INTO group_join_requests (conversation_id, user_id, status)
  VALUES (p_conversation_id, v_uid, 'pending')
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET status = 'pending', created_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION request_join_group(UUID) TO authenticated;

-- Get pending join requests (for group creator)
CREATE OR REPLACE FUNCTION get_group_join_requests(p_conversation_id UUID)
RETURNS TABLE (user_id UUID, user_name TEXT, company TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM conversations c WHERE c.id = p_conversation_id AND c.type = 'group' AND c.created_by = auth.uid()) THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT gjr.user_id,
    TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,''))::TEXT,
    p.company,
    gjr.created_at
  FROM group_join_requests gjr
  JOIN profiles p ON p.id = gjr.user_id
  WHERE gjr.conversation_id = p_conversation_id AND gjr.status = 'pending'
  ORDER BY gjr.created_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_group_join_requests(UUID) TO authenticated;

-- Accept join request (creator adds user to group)
CREATE OR REPLACE FUNCTION accept_group_join_request(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_created_by UUID;
BEGIN
  SELECT c.created_by INTO v_created_by FROM conversations c WHERE c.id = p_conversation_id AND c.type = 'group';
  IF v_created_by IS NULL OR v_created_by != auth.uid() THEN RAISE EXCEPTION 'Доступ запрещён'; END IF;
  UPDATE group_join_requests SET status = 'accepted' WHERE conversation_id = p_conversation_id AND user_id = p_user_id AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Заявка не найдена или уже обработана'; END IF;
  INSERT INTO conversation_participants (conversation_id, user_id) VALUES (p_conversation_id, p_user_id) ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION accept_group_join_request(UUID, UUID) TO authenticated;

-- Reject join request
CREATE OR REPLACE FUNCTION reject_group_join_request(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_created_by UUID;
BEGIN
  SELECT c.created_by INTO v_created_by FROM conversations c WHERE c.id = p_conversation_id AND c.type = 'group';
  IF v_created_by IS NULL OR v_created_by != auth.uid() THEN RAISE EXCEPTION 'Доступ запрещён'; END IF;
  UPDATE group_join_requests SET status = 'rejected' WHERE conversation_id = p_conversation_id AND user_id = p_user_id AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Заявка не найдена или уже обработана'; END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION reject_group_join_request(UUID, UUID) TO authenticated;

-- Update create_group_chat to accept optional description, is_open, category_id
CREATE OR REPLACE FUNCTION create_group_chat(p_title TEXT, p_user_ids UUID[], p_description TEXT DEFAULT NULL, p_is_open BOOLEAN DEFAULT false, p_category_id TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_cid UUID; v_id UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
  IF p_title IS NULL OR TRIM(p_title) = '' THEN RAISE EXCEPTION 'Укажите название чата'; END IF;
  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL OR array_length(p_user_ids, 1) < 1 THEN RAISE EXCEPTION 'Добавьте хотя бы одного участника'; END IF;
  INSERT INTO conversations (type, title, created_by, description, is_open, category_id)
  VALUES ('group', TRIM(p_title), v_uid, NULLIF(TRIM(COALESCE(p_description,'')), ''), COALESCE(p_is_open, false), NULLIF(TRIM(COALESCE(p_category_id,'')), ''))
  RETURNING id INTO v_cid;
  INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, v_uid);
  FOREACH v_id IN ARRAY p_user_ids LOOP
    IF v_id != v_uid THEN
      INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, v_id) ON CONFLICT (conversation_id, user_id) DO NOTHING;
    END IF;
  END LOOP;
  RETURN v_cid;
END;
$$;
GRANT EXECUTE ON FUNCTION create_group_chat(TEXT, UUID[], TEXT, BOOLEAN, TEXT) TO authenticated;

-- Allow updating group open/description/category (creator only)
CREATE OR REPLACE FUNCTION update_group_settings(p_conversation_id UUID, p_description TEXT DEFAULT NULL, p_is_open BOOLEAN DEFAULT NULL, p_category_id TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM conversations c WHERE c.id = p_conversation_id AND c.type = 'group' AND c.created_by = auth.uid()) THEN
    RAISE EXCEPTION 'Доступ запрещён';
  END IF;
  UPDATE conversations SET
    description = COALESCE(NULLIF(TRIM(p_description), ''), description),
    is_open = COALESCE(p_is_open, is_open),
    category_id = CASE WHEN p_category_id IS NOT NULL THEN NULLIF(TRIM(p_category_id), '') ELSE category_id END
  WHERE id = p_conversation_id;
END;
$$;
GRANT EXECUTE ON FUNCTION update_group_settings(UUID, TEXT, BOOLEAN, TEXT) TO authenticated;
