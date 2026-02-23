-- =============================================================================
-- ВЫПОЛНИТЕ ЭТОТ ФАЙЛ В SUPABASE: SQL Editor → New query → вставьте всё → Run
-- =============================================================================
-- Один раз скопируйте весь блок ниже и нажмите Run. Повторный запуск безопасен.

-- 0) Функция «он ли админ» (нужна для триггера и удаления профиля)
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND secret_word = 'admingrosskremeshova'); $$;

-- 1) Профиль создаётся при регистрации (имя, фамилия, компания из формы)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, first_name, last_name, company, secret_word, verified)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'first_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'company', ''),
    COALESCE(NEW.raw_user_meta_data->>'secret_word', ''),
    false
  );
  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2) Админ может одобрять/отклонять верификацию (кнопки в админке)
CREATE OR REPLACE FUNCTION profiles_verified_only_by_admin()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.verified IS DISTINCT FROM OLD.verified AND auth.uid() = OLD.id AND NOT is_admin() THEN
    NEW.verified := OLD.verified;
  END IF;
  RETURN NEW;
END;
$$;

-- 3) Удаление профиля при отклонении заявки (админ)
CREATE OR REPLACE FUNCTION admin_delete_profile(p_user_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  DELETE FROM profiles WHERE id = p_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_delete_profile(UUID) TO authenticated;

-- 4) Знакомства: заявки в друзья
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

-- 5) Ответы на комментарии (parent_id)
ALTER TABLE comments ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES comments(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id);

-- 6) Уведомления (чат «Администрация»)
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  payload JSONB DEFAULT '{}',
  read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notifications_select" ON notifications;
DROP POLICY IF EXISTS "notifications_update" ON notifications;
CREATE POLICY "notifications_select" ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "notifications_insert" ON notifications FOR INSERT WITH CHECK (true);
CREATE POLICY "notifications_update" ON notifications FOR UPDATE USING (auth.uid() = user_id);

-- 7) Чаты с друзьями: диалоги и сообщения
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL DEFAULT 'dm' CHECK (type IN ('dm', 'admin', 'ai')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conversation_participants_select" ON conversation_participants;
CREATE POLICY "conversation_participants_select" ON conversation_participants FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "conversation_participants_insert" ON conversation_participants FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "messages_select" ON messages;
DROP POLICY IF EXISTS "messages_insert" ON messages;
CREATE POLICY "messages_select" ON messages FOR SELECT USING (
  EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = messages.conversation_id AND cp.user_id = auth.uid())
);
CREATE POLICY "messages_insert" ON messages FOR INSERT WITH CHECK (
  sender_id = auth.uid() AND EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = messages.conversation_id AND cp.user_id = auth.uid())
);

-- Готово. После Run все функции и таблицы будут на месте.
