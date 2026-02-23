-- =============================================================================
-- BIZFORUM — ВЕСЬ SQL В ОДНОМ ФАЙЛЕ ДЛЯ SUPABASE SQL EDITOR
-- Скопируйте в Supabase: SQL Editor → New query → вставьте всё → Run
-- Повторный запуск безопасен (идемпотентно: IF NOT EXISTS, DROP IF EXISTS)
-- =============================================================================

-- ========== ЧАСТЬ 1: БАЗОВАЯ СХЕМА ==========
CREATE TABLE IF NOT EXISTS categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL
);
INSERT INTO categories (id, name, slug) VALUES
  ('startups', 'Стартапы', 'startups'),
  ('finance', 'Финансы', 'finance'),
  ('marketing', 'Маркетинг', 'marketing'),
  ('sales', 'Продажи', 'sales'),
  ('law', 'Юридическое', 'law'),
  ('tax', 'Налоги', 'tax'),
  ('hr', 'HR и команда', 'hr'),
  ('tech', 'IT и автоматизация', 'tech'),
  ('export', 'Экспорт и импорт', 'export'),
  ('everyday', 'Житейское', 'everyday')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  excerpt TEXT,
  body TEXT NOT NULL,
  author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  author_name TEXT NOT NULL DEFAULT 'Гость',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  author_name TEXT NOT NULL DEFAULT 'Гость',
  author_device_id TEXT,
  parent_id UUID REFERENCES comments(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS post_views (
  post_id UUID PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
  view_count BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS reactions (
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);
ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_type_check;
ALTER TABLE reactions ADD CONSTRAINT reactions_type_check CHECK (type IN ('muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha','useful'));

CREATE TABLE IF NOT EXISTS favorites (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name TEXT NOT NULL DEFAULT '',
  last_name TEXT NOT NULL DEFAULT '',
  company TEXT NOT NULL DEFAULT '',
  secret_word TEXT NOT NULL DEFAULT '',
  verified BOOLEAN NOT NULL DEFAULT false,
  avatar_url TEXT,
  date_of_birth DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS friend_requests (
  from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (from_user_id, to_user_id)
);

CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_from ON friend_requests(from_user_id);
CREATE INDEX IF NOT EXISTS idx_posts_category ON posts(category_id);
CREATE INDEX IF NOT EXISTS idx_posts_created ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comments_post ON comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id) WHERE parent_id IS NOT NULL;

-- Медиа и полнотекстовый поиск для постов
ALTER TABLE posts ADD COLUMN IF NOT EXISTS media_urls JSONB DEFAULT '[]';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS search_vector tsvector;
CREATE INDEX IF NOT EXISTS idx_posts_search ON posts USING gin(search_vector);
CREATE OR REPLACE FUNCTION posts_search_trigger() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := setweight(to_tsvector('russian', coalesce(NEW.title, '')), 'A') || setweight(to_tsvector('russian', coalesce(NEW.body, '')), 'B');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS posts_search_update ON posts;
CREATE TRIGGER posts_search_update BEFORE INSERT OR UPDATE OF title, body ON posts FOR EACH ROW EXECUTE FUNCTION posts_search_trigger();

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE friend_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "friend_requests_select" ON friend_requests;
DROP POLICY IF EXISTS "friend_requests_insert" ON friend_requests;
DROP POLICY IF EXISTS "friend_requests_update" ON friend_requests;
CREATE POLICY "friend_requests_select" ON friend_requests FOR SELECT USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);
CREATE POLICY "friend_requests_insert" ON friend_requests FOR INSERT WITH CHECK (auth.uid() = from_user_id);
CREATE POLICY "friend_requests_update" ON friend_requests FOR UPDATE USING (auth.uid() = to_user_id);

DROP POLICY IF EXISTS "categories_select" ON categories;
CREATE POLICY "categories_select" ON categories FOR SELECT USING (true);

DROP POLICY IF EXISTS "posts_select" ON posts;
DROP POLICY IF EXISTS "posts_insert" ON posts;
DROP POLICY IF EXISTS "posts_update" ON posts;
DROP POLICY IF EXISTS "posts_delete" ON posts;
CREATE POLICY "posts_select" ON posts FOR SELECT USING (true);
CREATE POLICY "posts_insert" ON posts FOR INSERT WITH CHECK (true);
CREATE POLICY "posts_update" ON posts FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "posts_delete" ON posts FOR DELETE USING (auth.uid() = author_id);

DROP POLICY IF EXISTS "comments_select" ON comments;
DROP POLICY IF EXISTS "comments_insert" ON comments;
DROP POLICY IF EXISTS "comments_update" ON comments;
DROP POLICY IF EXISTS "comments_delete" ON comments;
CREATE POLICY "comments_select" ON comments FOR SELECT USING (true);
CREATE POLICY "comments_insert" ON comments FOR INSERT WITH CHECK (true);
CREATE POLICY "comments_update" ON comments FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "comments_delete" ON comments FOR DELETE USING (auth.uid() = author_id);

DROP POLICY IF EXISTS "post_views_select" ON post_views;
DROP POLICY IF EXISTS "post_views_all" ON post_views;
CREATE POLICY "post_views_select" ON post_views FOR SELECT USING (true);
CREATE POLICY "post_views_all" ON post_views FOR ALL USING (true);

DROP POLICY IF EXISTS "reactions_select" ON reactions;
DROP POLICY IF EXISTS "reactions_insert" ON reactions;
DROP POLICY IF EXISTS "reactions_update" ON reactions;
DROP POLICY IF EXISTS "reactions_delete" ON reactions;
CREATE POLICY "reactions_select" ON reactions FOR SELECT USING (true);
CREATE POLICY "reactions_insert" ON reactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "reactions_update" ON reactions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "reactions_delete" ON reactions FOR DELETE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "favorites_select" ON favorites;
DROP POLICY IF EXISTS "favorites_insert" ON favorites;
DROP POLICY IF EXISTS "favorites_delete" ON favorites;
CREATE POLICY "favorites_select" ON favorites FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "favorites_insert" ON favorites FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "favorites_delete" ON favorites FOR DELETE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "profiles_select" ON profiles;
DROP POLICY IF EXISTS "profiles_insert" ON profiles;
DROP POLICY IF EXISTS "profiles_update" ON profiles;
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "profiles_insert" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (auth.uid() = id);

-- Профиль создаётся при регистрации
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, first_name, last_name, company, secret_word, verified)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'first_name', ''), COALESCE(NEW.raw_user_meta_data->>'last_name', ''), COALESCE(NEW.raw_user_meta_data->>'company', ''), COALESCE(NEW.raw_user_meta_data->>'secret_word', ''), false);
  RETURN NEW;
EXCEPTION WHEN unique_violation THEN RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE OR REPLACE FUNCTION increment_post_view(p_post_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN INSERT INTO post_views (post_id, view_count) VALUES (p_post_id, 1) ON CONFLICT (post_id) DO UPDATE SET view_count = post_views.view_count + 1; END; $$;
GRANT EXECUTE ON FUNCTION increment_post_view(UUID) TO anon;
GRANT EXECUTE ON FUNCTION increment_post_view(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND secret_word = 'admingrosskremeshova'); $$;

CREATE OR REPLACE FUNCTION profiles_verified_only_by_admin()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF NEW.verified IS DISTINCT FROM OLD.verified AND auth.uid() = OLD.id AND NOT is_admin() THEN NEW.verified := OLD.verified; END IF; RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS tr_profiles_verified ON profiles;
CREATE TRIGGER tr_profiles_verified BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION profiles_verified_only_by_admin();

CREATE OR REPLACE FUNCTION admin_list_profiles() RETURNS SETOF profiles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF NOT is_admin() THEN RETURN; END IF; RETURN QUERY SELECT * FROM profiles ORDER BY created_at DESC; END; $$;
CREATE OR REPLACE FUNCTION admin_delete_comment(p_comment_id UUID) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF is_admin() THEN DELETE FROM comments WHERE id = p_comment_id; END IF; END; $$;
CREATE OR REPLACE FUNCTION admin_delete_post(p_post_id UUID) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF is_admin() THEN DELETE FROM posts WHERE id = p_post_id; END IF; END; $$;
CREATE OR REPLACE FUNCTION admin_update_post(p_post_id UUID, p_title TEXT, p_body TEXT) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF NOT is_admin() THEN RETURN; END IF; UPDATE posts SET title = COALESCE(p_title, title), body = COALESCE(p_body, body) WHERE id = p_post_id; END; $$;
CREATE OR REPLACE FUNCTION admin_delete_profile(p_user_id UUID) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF NOT is_admin() THEN RETURN; END IF; DELETE FROM profiles WHERE id = p_user_id; END; $$;

CREATE OR REPLACE FUNCTION search_profiles_for_friends(p_query TEXT)
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, company TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN RETURN QUERY SELECT pr.id, pr.first_name, pr.last_name, pr.company FROM profiles pr WHERE pr.id != auth.uid() AND pr.verified = true AND (p_query IS NULL OR trim(p_query) = '' OR pr.first_name ILIKE '%' || trim(p_query) || '%' OR pr.last_name ILIKE '%' || trim(p_query) || '%' OR pr.company ILIKE '%' || trim(p_query) || '%') ORDER BY lower(pr.first_name), lower(pr.last_name) LIMIT 100; END; $$;
GRANT EXECUTE ON FUNCTION search_profiles_for_friends(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION get_profiles_public(p_ids UUID[])
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, company TEXT) LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$ SELECT pr.id, pr.first_name, pr.last_name, pr.company FROM profiles pr WHERE pr.id = ANY(p_ids); $$;
GRANT EXECUTE ON FUNCTION get_profiles_public(UUID[]) TO authenticated;

GRANT EXECUTE ON FUNCTION admin_list_profiles() TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_profile(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_comment(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_post(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_post(UUID, TEXT, TEXT) TO authenticated;

-- ========== ЧАСТЬ 2: УВЕДОМЛЕНИЯ, ЧАТЫ, ПОДПИСКИ ==========
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
DROP POLICY IF EXISTS "notifications_insert" ON notifications;
CREATE POLICY "notifications_select" ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "notifications_insert" ON notifications FOR INSERT WITH CHECK (true);
CREATE POLICY "notifications_update" ON notifications FOR UPDATE USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL DEFAULT 'dm' CHECK (type IN ('dm', 'admin', 'ai', 'group')),
  title TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
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
DROP POLICY IF EXISTS "conversation_participants_insert" ON conversation_participants;
CREATE POLICY "conversation_participants_select" ON conversation_participants FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "conversation_participants_insert" ON conversation_participants FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "messages_select" ON messages;
DROP POLICY IF EXISTS "messages_insert" ON messages;
CREATE POLICY "messages_select" ON messages FOR SELECT USING (EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = messages.conversation_id AND cp.user_id = auth.uid()));
CREATE POLICY "messages_insert" ON messages FOR INSERT WITH CHECK (sender_id = auth.uid() AND EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = messages.conversation_id AND cp.user_id = auth.uid()));

ALTER TABLE posts ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published';
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_status_check;
ALTER TABLE posts ADD CONSTRAINT posts_status_check CHECK (status IN ('draft', 'published'));
ALTER TABLE posts ADD COLUMN IF NOT EXISTS price INTEGER;
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_price_non_negative;
ALTER TABLE posts ADD CONSTRAINT posts_price_non_negative CHECK (price IS NULL OR price >= 0);

INSERT INTO categories (id, name, slug) VALUES ('useful', 'Полезное', 'useful'), ('partnership', 'Ищу партнерства', 'partnership') ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION create_or_get_admin_conversation(p_user_id UUID) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_cid UUID; BEGIN IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN RAISE EXCEPTION 'Только владелец'; END IF; SELECT c.id INTO v_cid FROM conversations c JOIN conversation_participants cp ON cp.conversation_id = c.id WHERE c.type = 'admin' AND cp.user_id = p_user_id LIMIT 1; IF v_cid IS NOT NULL THEN RETURN v_cid; END IF; INSERT INTO conversations (type) VALUES ('admin') RETURNING id INTO v_cid; INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, p_user_id); RETURN v_cid; END; $$;
GRANT EXECUTE ON FUNCTION create_or_get_admin_conversation(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION get_admin_conversations_list()
RETURNS TABLE(conversation_id UUID, user_id UUID, user_name TEXT, last_body TEXT, last_created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
BEGIN IF NOT is_admin() THEN RETURN; END IF;
RETURN QUERY SELECT c.id, cp.user_id, TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,''))::TEXT, m.body, m.created_at
FROM conversations c JOIN conversation_participants cp ON cp.conversation_id = c.id LEFT JOIN profiles p ON p.id = cp.user_id
LEFT JOIN LATERAL (SELECT body, created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) m ON true
WHERE c.type = 'admin' ORDER BY m.created_at DESC NULLS LAST; END; $$;
GRANT EXECUTE ON FUNCTION get_admin_conversations_list() TO authenticated;

CREATE OR REPLACE FUNCTION admin_send_message(p_conv_id UUID, p_body TEXT) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_msg_id UUID; BEGIN IF NOT is_admin() OR p_body IS NULL OR trim(p_body) = '' THEN RAISE EXCEPTION 'Доступ запрещён'; END IF; IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conv_id AND type = 'admin') THEN RAISE EXCEPTION 'Диалог не найден'; END IF; INSERT INTO messages (conversation_id, sender_id, body) VALUES (p_conv_id, auth.uid(), trim(p_body)) RETURNING id INTO v_msg_id; RETURN v_msg_id; END; $$;
GRANT EXECUTE ON FUNCTION admin_send_message(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION admin_get_messages(p_conv_id UUID)
RETURNS TABLE(msg_id UUID, sender_id UUID, body TEXT, created_at TIMESTAMPTZ) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$ BEGIN IF NOT is_admin() THEN RETURN; END IF; IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conv_id AND type = 'admin') THEN RETURN; END IF; RETURN QUERY SELECT m.id, m.sender_id, m.body, m.created_at FROM messages m WHERE m.conversation_id = p_conv_id ORDER BY m.created_at ASC; END; $$;
GRANT EXECUTE ON FUNCTION admin_get_messages(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION notify_on_admin_chat_message() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_conv_type TEXT; v_sender_is_admin BOOLEAN; r RECORD;
BEGIN SELECT c.type INTO v_conv_type FROM conversations c WHERE c.id = NEW.conversation_id;
IF v_conv_type IS NULL OR v_conv_type != 'admin' THEN RETURN NEW; END IF;
SELECT EXISTS (SELECT 1 FROM profiles WHERE id = NEW.sender_id AND secret_word = 'admingrosskremeshova') INTO v_sender_is_admin;
IF v_sender_is_admin THEN FOR r IN SELECT cp.user_id FROM conversation_participants cp WHERE cp.conversation_id = NEW.conversation_id AND cp.user_id != NEW.sender_id LOOP INSERT INTO notifications (user_id, type, payload, read) VALUES (r.user_id, 'message_reply', jsonb_build_object('conversation_id', NEW.conversation_id, 'from_user_id', NEW.sender_id, 'message_id', NEW.id), false); END LOOP;
ELSE FOR r IN SELECT id FROM profiles WHERE secret_word = 'admingrosskremeshova' AND id != NEW.sender_id LOOP INSERT INTO notifications (user_id, type, payload, read) VALUES (r.id, 'message_reply', jsonb_build_object('conversation_id', NEW.conversation_id, 'from_user_id', NEW.sender_id, 'message_id', NEW.id), false); END LOOP; END IF;
RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS tr_notify_on_admin_chat ON messages;
CREATE TRIGGER tr_notify_on_admin_chat AFTER INSERT ON messages FOR EACH ROW EXECUTE FUNCTION notify_on_admin_chat_message();

CREATE OR REPLACE FUNCTION create_dm_conversation(p_other_user_id UUID) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_uid UUID := auth.uid(); v_cid UUID; BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF; IF p_other_user_id = v_uid THEN RAISE EXCEPTION 'Нельзя создать чат с самим собой'; END IF; SELECT c.id INTO v_cid FROM conversations c JOIN conversation_participants cp1 ON cp1.conversation_id = c.id AND cp1.user_id = v_uid JOIN conversation_participants cp2 ON cp2.conversation_id = c.id AND cp2.user_id = p_other_user_id WHERE c.type = 'dm' ORDER BY c.created_at ASC LIMIT 1; IF v_cid IS NOT NULL THEN RETURN v_cid; END IF; INSERT INTO conversations (type) VALUES ('dm') RETURNING id INTO v_cid; INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, v_uid), (v_cid, p_other_user_id); RETURN v_cid; END; $$;
GRANT EXECUTE ON FUNCTION create_dm_conversation(UUID) TO authenticated;

-- Групповые чаты
CREATE OR REPLACE FUNCTION create_group_chat(p_title TEXT, p_user_ids UUID[]) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_uid UUID := auth.uid(); v_cid UUID; v_id UUID; BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF; IF p_title IS NULL OR TRIM(p_title) = '' THEN RAISE EXCEPTION 'Укажите название чата'; END IF; IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL OR array_length(p_user_ids, 1) < 1 THEN RAISE EXCEPTION 'Добавьте хотя бы одного участника'; END IF; INSERT INTO conversations (type, title, created_by) VALUES ('group', TRIM(p_title), v_uid) RETURNING id INTO v_cid; INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, v_uid); FOREACH v_id IN ARRAY p_user_ids LOOP IF v_id != v_uid THEN INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, v_id) ON CONFLICT (conversation_id, user_id) DO NOTHING; END IF; END LOOP; RETURN v_cid; END; $$;
GRANT EXECUTE ON FUNCTION create_group_chat(TEXT, UUID[]) TO authenticated;

CREATE OR REPLACE FUNCTION remove_participant_from_group(p_conversation_id UUID, p_user_id UUID) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_uid UUID := auth.uid(); v_created_by UUID; v_type TEXT; BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF; SELECT type, created_by INTO v_type, v_created_by FROM conversations WHERE id = p_conversation_id; IF v_type IS NULL OR v_type != 'group' THEN RAISE EXCEPTION 'Чат не найден'; END IF; IF v_created_by != v_uid THEN RAISE EXCEPTION 'Только создатель чата может удалять участников'; END IF; IF p_user_id = v_uid THEN RAISE EXCEPTION 'Нельзя удалить самого себя'; END IF; DELETE FROM conversation_participants WHERE conversation_id = p_conversation_id AND user_id = p_user_id; END; $$;
GRANT EXECUTE ON FUNCTION remove_participant_from_group(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION add_participant_to_group(p_conversation_id UUID, p_user_id UUID) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_uid UUID := auth.uid(); v_created_by UUID; v_type TEXT; BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF; SELECT type, created_by INTO v_type, v_created_by FROM conversations WHERE id = p_conversation_id; IF v_type IS NULL OR v_type != 'group' THEN RAISE EXCEPTION 'Чат не найден'; END IF; IF v_created_by != v_uid THEN RAISE EXCEPTION 'Только создатель чата может добавлять участников'; END IF; INSERT INTO conversation_participants (conversation_id, user_id) VALUES (p_conversation_id, p_user_id) ON CONFLICT (conversation_id, user_id) DO NOTHING; END; $$;
GRANT EXECUTE ON FUNCTION add_participant_to_group(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION get_group_participants(p_conversation_id UUID) RETURNS TABLE (user_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN RETURN QUERY SELECT cp.user_id FROM conversation_participants cp JOIN conversations c ON c.id = cp.conversation_id WHERE cp.conversation_id = p_conversation_id AND c.type = 'group' AND EXISTS (SELECT 1 FROM conversation_participants cp2 WHERE cp2.conversation_id = p_conversation_id AND cp2.user_id = auth.uid()); END; $$;
GRANT EXECUTE ON FUNCTION get_group_participants(UUID) TO authenticated;

CREATE TABLE IF NOT EXISTS subscriptions (user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, author_id), CHECK (user_id != author_id));
CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id);
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "subscriptions_select" ON subscriptions;
DROP POLICY IF EXISTS "subscriptions_insert" ON subscriptions;
DROP POLICY IF EXISTS "subscriptions_delete" ON subscriptions;
CREATE POLICY "subscriptions_select" ON subscriptions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "subscriptions_insert" ON subscriptions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "subscriptions_delete" ON subscriptions FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS company_stage TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS balance INTEGER NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS subscription_ends_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS mfa_enabled BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS post_purchases (user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE, amount INTEGER NOT NULL CHECK (amount > 0), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, post_id));
CREATE INDEX IF NOT EXISTS idx_post_purchases_user ON post_purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_post_purchases_post ON post_purchases(post_id);
ALTER TABLE post_purchases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "post_purchases_select" ON post_purchases;
DROP POLICY IF EXISTS "post_purchases_insert" ON post_purchases;
CREATE POLICY "post_purchases_select" ON post_purchases FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "post_purchases_insert" ON post_purchases FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS post_opens (user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, post_id));
CREATE INDEX IF NOT EXISTS idx_post_opens_user_created ON post_opens(user_id, created_at);
ALTER TABLE post_opens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "post_opens_select" ON post_opens;
DROP POLICY IF EXISTS "post_opens_insert" ON post_opens;
CREATE POLICY "post_opens_select" ON post_opens FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "post_opens_insert" ON post_opens FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION buy_post(p_post_id UUID) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_price INTEGER; v_author_id UUID; v_buyer_bal INTEGER; v_author_bal INTEGER;
BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
SELECT p.price, p.author_id INTO v_price, v_author_id FROM posts p WHERE p.id = p_post_id AND p.status = 'published';
IF v_price IS NULL OR v_price <= 0 THEN RAISE EXCEPTION 'Пост не платный'; END IF;
IF v_author_id = v_uid THEN RAISE EXCEPTION 'Нельзя купить свой пост'; END IF;
IF EXISTS (SELECT 1 FROM post_purchases WHERE user_id = v_uid AND post_id = p_post_id) THEN RAISE EXCEPTION 'Вы уже купили этот пост'; END IF;
SELECT COALESCE(balance, 0) INTO v_buyer_bal FROM profiles WHERE id = v_uid;
IF v_buyer_bal < v_price THEN RAISE EXCEPTION 'Недостаточно средств'; END IF;
SELECT COALESCE(balance, 0) INTO v_author_bal FROM profiles WHERE id = v_author_id;
UPDATE profiles SET balance = balance - v_price, updated_at = now() WHERE id = v_uid;
UPDATE profiles SET balance = balance + v_price, updated_at = now() WHERE id = v_author_id;
INSERT INTO post_purchases (user_id, post_id, amount) VALUES (v_uid, p_post_id, v_price); END; $$;
GRANT EXECUTE ON FUNCTION buy_post(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION admin_add_balance(p_user_id UUID, p_amount INTEGER) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF NOT is_admin() THEN RAISE EXCEPTION 'Доступ запрещён'; END IF; IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Сумма должна быть положительной'; END IF; UPDATE profiles SET balance = COALESCE(balance, 0) + p_amount, updated_at = now() WHERE id = p_user_id; END; $$;
GRANT EXECUTE ON FUNCTION admin_add_balance(UUID, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION user_topup_balance(p_amount INTEGER) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_uid UUID := auth.uid(); BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF; IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Сумма должна быть положительной'; END IF; UPDATE profiles SET balance = COALESCE(balance, 0) + p_amount, updated_at = now() WHERE id = v_uid; END; $$;
GRANT EXECUTE ON FUNCTION user_topup_balance(INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION get_subscriber_count(p_author_id UUID) RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$ SELECT count(*)::int FROM subscriptions WHERE author_id = p_author_id; $$;
GRANT EXECUTE ON FUNCTION get_subscriber_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_subscriber_count(UUID) TO anon;

-- ========== ЧАСТЬ 3: РЕАКЦИИ НА КОММЕНТАРИЯХ, ЛУЧШИЙ ОТВЕТ, БЕЙДЖИ ==========
CREATE TABLE IF NOT EXISTS comment_reactions (comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE, user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, type TEXT NOT NULL CHECK (type IN ('muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha','useful')), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (comment_id, user_id));
CREATE INDEX IF NOT EXISTS idx_comment_reactions_comment ON comment_reactions(comment_id);
ALTER TABLE comment_reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "comment_reactions_select" ON comment_reactions;
DROP POLICY IF EXISTS "comment_reactions_insert" ON comment_reactions;
DROP POLICY IF EXISTS "comment_reactions_delete" ON comment_reactions;
CREATE POLICY "comment_reactions_select" ON comment_reactions FOR SELECT USING (true);
CREATE POLICY "comment_reactions_insert" ON comment_reactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "comment_reactions_delete" ON comment_reactions FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE posts ADD COLUMN IF NOT EXISTS best_answer_comment_id UUID REFERENCES comments(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_posts_best_answer ON posts(best_answer_comment_id) WHERE best_answer_comment_id IS NOT NULL;

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_company_stage_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_company_stage_check CHECK (company_stage IS NULL OR company_stage IN ('idea','startup_1_3','startup_3_5','growth','enterprise','other'));

CREATE TABLE IF NOT EXISTS badges (id TEXT PRIMARY KEY, name_ru TEXT NOT NULL, description_ru TEXT, icon TEXT, rule_type TEXT NOT NULL DEFAULT 'computed' CHECK (rule_type IN ('computed','assigned')));
INSERT INTO badges (id, name_ru, description_ru, rule_type) VALUES ('helped_10', 'Помог 10 раз', '10+ полезных ответов', 'computed'), ('helped_50', 'Помог 50 раз', '50+ полезных ответов', 'computed'), ('helped_100', 'Помог 100 раз', '100+ полезных ответов', 'computed'), ('startup_1_3', 'Стартап 1–3 года', 'Компания на этапе 1–3 года', 'computed'), ('startup_3_5', 'Стартап 3–5 лет', 'Компания на этапе 3–5 лет', 'computed'), ('expert_marketing', 'Эксперт по маркетингу', 'Активность в категории Маркетинг', 'computed'), ('expert_finance', 'Эксперт по финансам', 'Активность в категории Финансы', 'computed'), ('expert_sales', 'Эксперт по продажам', 'Активность в категории Продажи', 'computed') ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS user_badges (user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, badge_id TEXT NOT NULL REFERENCES badges(id) ON DELETE CASCADE, earned_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, badge_id));
CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "user_badges_select" ON user_badges;
DROP POLICY IF EXISTS "user_badges_insert" ON user_badges;
DROP POLICY IF EXISTS "user_badges_delete" ON user_badges;
CREATE POLICY "user_badges_select" ON user_badges FOR SELECT USING (true);
CREATE POLICY "user_badges_insert" ON user_badges FOR INSERT WITH CHECK (is_admin());
CREATE POLICY "user_badges_delete" ON user_badges FOR DELETE USING (is_admin());

CREATE OR REPLACE FUNCTION admin_set_best_answer(p_post_id UUID, p_comment_id UUID) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ BEGIN IF NOT is_admin() THEN RETURN; END IF; UPDATE posts SET best_answer_comment_id = p_comment_id WHERE id = p_post_id; END; $$;
GRANT EXECUTE ON FUNCTION admin_set_best_answer(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION get_user_badges(p_user_id UUID) RETURNS TABLE(badge_id TEXT, name_ru TEXT, description_ru TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$ DECLARE helpful_cnt BIGINT; stage TEXT; BEGIN SELECT pr.company_stage INTO stage FROM profiles pr WHERE pr.id = p_user_id; SELECT COUNT(DISTINCT cr.comment_id) INTO helpful_cnt FROM comments c JOIN comment_reactions cr ON cr.comment_id = c.id AND cr.type = 'useful' WHERE c.author_id = p_user_id; RETURN QUERY SELECT ub.badge_id, b.name_ru, b.description_ru FROM user_badges ub JOIN badges b ON b.id = ub.badge_id WHERE ub.user_id = p_user_id; IF helpful_cnt >= 100 THEN RETURN QUERY SELECT 'helped_100'::TEXT, 'Помог 100 раз'::TEXT, '100+ полезных ответов'::TEXT; END IF; IF helpful_cnt >= 50 THEN RETURN QUERY SELECT 'helped_50'::TEXT, 'Помог 50 раз'::TEXT, '50+ полезных ответов'::TEXT; END IF; IF helpful_cnt >= 10 THEN RETURN QUERY SELECT 'helped_10'::TEXT, 'Помог 10 раз'::TEXT, '10+ полезных ответов'::TEXT; END IF; IF stage = 'startup_1_3' THEN RETURN QUERY SELECT 'startup_1_3'::TEXT, 'Стартап 1–3 года'::TEXT, 'Компания на этапе 1–3 года'::TEXT; END IF; IF stage = 'startup_3_5' THEN RETURN QUERY SELECT 'startup_3_5'::TEXT, 'Стартап 3–5 лет'::TEXT, 'Компания на этапе 3–5 лет'::TEXT; END IF; END; $$;
GRANT EXECUTE ON FUNCTION get_user_badges(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_badges(UUID) TO anon;

-- ========== ЧАСТЬ 4: ПРОЧИТАННЫЕ СООБЩЕНИЯ, UNREAD, DM/ГРУППЫ ==========
CREATE TABLE IF NOT EXISTS conversation_last_read (user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, last_read_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, conversation_id));
CREATE INDEX IF NOT EXISTS idx_conversation_last_read_user ON conversation_last_read(user_id);
ALTER TABLE conversation_last_read ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conversation_last_read_select" ON conversation_last_read;
DROP POLICY IF EXISTS "conversation_last_read_insert" ON conversation_last_read;
DROP POLICY IF EXISTS "conversation_last_read_update" ON conversation_last_read;
CREATE POLICY "conversation_last_read_select" ON conversation_last_read FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "conversation_last_read_insert" ON conversation_last_read FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "conversation_last_read_update" ON conversation_last_read FOR UPDATE USING (auth.uid() = user_id);

-- Удаляем старые версии функций (если менялся тип возврата)
DROP FUNCTION IF EXISTS get_dm_conversations_with_preview();
DROP FUNCTION IF EXISTS get_group_conversations_with_preview();

CREATE OR REPLACE FUNCTION get_dm_conversations_with_preview()
RETURNS TABLE (conversation_id UUID, other_user_id UUID, other_name TEXT, last_body TEXT, last_created_at TIMESTAMPTZ, unread_count BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN IF v_uid IS NULL THEN RETURN; END IF;
RETURN QUERY WITH my_dms AS (SELECT cp.conversation_id FROM conversation_participants cp JOIN conversations c ON c.id = cp.conversation_id WHERE cp.user_id = v_uid AND c.type = 'dm'),
other_participant AS (SELECT cp.conversation_id, cp.user_id AS other_id FROM conversation_participants cp JOIN my_dms m ON m.conversation_id = cp.conversation_id WHERE cp.user_id != v_uid),
last_msg AS (SELECT DISTINCT ON (m.conversation_id) m.conversation_id, m.body, m.created_at FROM messages m JOIN my_dms d ON d.conversation_id = m.conversation_id ORDER BY m.conversation_id, m.created_at DESC),
unread AS (SELECT m.conversation_id, COUNT(*)::BIGINT AS cnt FROM messages m JOIN my_dms d ON d.conversation_id = m.conversation_id LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = v_uid WHERE m.sender_id != v_uid AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at) GROUP BY m.conversation_id)
SELECT op.conversation_id, op.other_id, COALESCE(TRIM(p.first_name || ' ' || p.last_name), p.company, '—')::TEXT, lm.body, lm.created_at, COALESCE(u.cnt, 0)::BIGINT
FROM other_participant op LEFT JOIN last_msg lm ON lm.conversation_id = op.conversation_id LEFT JOIN profiles p ON p.id = op.other_id LEFT JOIN unread u ON u.conversation_id = op.conversation_id ORDER BY lm.created_at DESC NULLS LAST;
END; $$;
GRANT EXECUTE ON FUNCTION get_dm_conversations_with_preview() TO authenticated;

CREATE OR REPLACE FUNCTION get_group_conversations_with_preview()
RETURNS TABLE (conversation_id UUID, title TEXT, created_by UUID, last_body TEXT, last_created_at TIMESTAMPTZ, unread_count BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN IF v_uid IS NULL THEN RETURN; END IF;
RETURN QUERY WITH my_groups AS (SELECT cp.conversation_id FROM conversation_participants cp JOIN conversations c ON c.id = cp.conversation_id WHERE cp.user_id = v_uid AND c.type = 'group'),
last_msg AS (SELECT DISTINCT ON (m.conversation_id) m.conversation_id, m.body, m.created_at FROM messages m JOIN my_groups g ON g.conversation_id = m.conversation_id ORDER BY m.conversation_id, m.created_at DESC),
unread AS (SELECT m.conversation_id, COUNT(*)::BIGINT AS cnt FROM messages m JOIN my_groups g ON g.conversation_id = m.conversation_id LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = v_uid WHERE m.sender_id != v_uid AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at) GROUP BY m.conversation_id)
SELECT c.id, c.title, c.created_by, lm.body, lm.created_at, COALESCE(u.cnt, 0)::BIGINT
FROM conversations c JOIN my_groups g ON g.conversation_id = c.id LEFT JOIN last_msg lm ON lm.conversation_id = c.id LEFT JOIN unread u ON u.conversation_id = c.id ORDER BY lm.created_at DESC NULLS LAST;
END; $$;
GRANT EXECUTE ON FUNCTION get_group_conversations_with_preview() TO authenticated;

CREATE OR REPLACE FUNCTION mark_conversation_read(p_conversation_id UUID) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF auth.uid() IS NULL THEN RETURN; END IF; INSERT INTO conversation_last_read (user_id, conversation_id, last_read_at) VALUES (auth.uid(), p_conversation_id, now()) ON CONFLICT (user_id, conversation_id) DO UPDATE SET last_read_at = now(); END; $$;
GRANT EXECUTE ON FUNCTION mark_conversation_read(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION get_total_unread_chat_count() RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_total BIGINT := 0;
BEGIN IF auth.uid() IS NULL THEN RETURN 0; END IF;
SELECT COUNT(*)::BIGINT INTO v_total FROM messages m JOIN conversation_participants cp ON cp.conversation_id = m.conversation_id AND cp.user_id = auth.uid()
LEFT JOIN conversation_last_read clr ON clr.conversation_id = m.conversation_id AND clr.user_id = auth.uid()
WHERE m.sender_id != auth.uid() AND (clr.last_read_at IS NULL OR m.created_at > clr.last_read_at);
RETURN v_total; END; $$;
GRANT EXECUTE ON FUNCTION get_total_unread_chat_count() TO authenticated;

-- ========== ЧАСТЬ 5: ПОДПИСКА, admin_update_profile, ЖАЛОБЫ ==========
CREATE OR REPLACE FUNCTION get_subscription_status() RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE v_uid UUID := auth.uid(); v_ends TIMESTAMPTZ; v_opens INT; v_limit INT := 2;
BEGIN IF v_uid IS NULL THEN RETURN jsonb_build_object('has_subscription', false, 'opens_remaining', 0); END IF;
SELECT subscription_ends_at INTO v_ends FROM profiles WHERE id = v_uid;
IF v_ends IS NOT NULL AND v_ends > now() THEN RETURN jsonb_build_object('has_subscription', true, 'opens_remaining', v_limit); END IF;
SELECT count(*)::int INTO v_opens FROM post_opens WHERE user_id = v_uid AND created_at >= date_trunc('month', now());
RETURN jsonb_build_object('has_subscription', false, 'opens_remaining', GREATEST(0, v_limit - v_opens)); END; $$;
GRANT EXECUTE ON FUNCTION get_subscription_status() TO authenticated;
GRANT EXECUTE ON FUNCTION get_subscription_status() TO anon;

CREATE OR REPLACE FUNCTION use_post_open(p_post_id UUID) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ends TIMESTAMPTZ; v_opens INT; v_already BOOLEAN;
BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
SELECT subscription_ends_at INTO v_ends FROM profiles WHERE id = v_uid;
IF v_ends IS NOT NULL AND v_ends > now() THEN RETURN jsonb_build_object('ok', true, 'opens_remaining', 2); END IF;
SELECT EXISTS (SELECT 1 FROM post_opens WHERE user_id = v_uid AND post_id = p_post_id) INTO v_already;
IF v_already THEN SELECT count(*)::int INTO v_opens FROM post_opens WHERE user_id = v_uid AND created_at >= date_trunc('month', now()); RETURN jsonb_build_object('ok', true, 'opens_remaining', GREATEST(0, 2 - v_opens)); END IF;
SELECT count(*)::int INTO v_opens FROM post_opens WHERE user_id = v_uid AND created_at >= date_trunc('month', now());
IF v_opens >= 2 THEN RAISE EXCEPTION 'post_opens_limit'; END IF;
INSERT INTO post_opens (user_id, post_id) VALUES (v_uid, p_post_id) ON CONFLICT (user_id, post_id) DO NOTHING;
RETURN jsonb_build_object('ok', true, 'opens_remaining', GREATEST(0, 2 - v_opens - 1)); END; $$;
GRANT EXECUTE ON FUNCTION use_post_open(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION has_opened_post(p_post_id UUID) RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$ SELECT EXISTS (SELECT 1 FROM post_opens WHERE user_id = auth.uid() AND post_id = p_post_id); $$;
GRANT EXECUTE ON FUNCTION has_opened_post(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION has_opened_post(UUID) TO anon;

CREATE OR REPLACE FUNCTION get_opened_post_ids() RETURNS UUID[] LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$ SELECT COALESCE(array_agg(post_id), ARRAY[]::UUID[]) FROM post_opens WHERE user_id = auth.uid(); $$;
GRANT EXECUTE ON FUNCTION get_opened_post_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION get_opened_post_ids() TO anon;

CREATE OR REPLACE FUNCTION get_subscriber_counts(p_author_ids UUID[]) RETURNS TABLE(author_id UUID, cnt BIGINT) LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$ SELECT s.author_id, count(*)::BIGINT FROM subscriptions s WHERE s.author_id = ANY(p_author_ids) GROUP BY s.author_id; $$;
GRANT EXECUTE ON FUNCTION get_subscriber_counts(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_subscriber_counts(UUID[]) TO anon;

DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER);
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_update_profile(p_id UUID, p_first_name TEXT, p_last_name TEXT, p_company TEXT, p_verified BOOLEAN, p_company_stage TEXT DEFAULT NULL, p_balance INTEGER DEFAULT NULL, p_subscription_ends_at TIMESTAMPTZ DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN IF NOT is_admin() THEN RETURN; END IF;
UPDATE profiles SET first_name = COALESCE(p_first_name, first_name), last_name = COALESCE(p_last_name, last_name), company = COALESCE(p_company, company), verified = COALESCE(p_verified, verified), company_stage = COALESCE(p_company_stage, company_stage), balance = CASE WHEN p_balance IS NOT NULL THEN p_balance ELSE balance END, subscription_ends_at = CASE WHEN p_subscription_ends_at IS NOT NULL THEN p_subscription_ends_at ELSE subscription_ends_at END, updated_at = now() WHERE id = p_id; END; $$;
GRANT EXECUTE ON FUNCTION admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER, TIMESTAMPTZ) TO authenticated;

-- Жалобы и чёрный список
CREATE TABLE IF NOT EXISTS reports (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, target_type TEXT NOT NULL CHECK (target_type IN ('post', 'comment')), target_id UUID NOT NULL, reason TEXT, status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')), admin_note TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), resolved_at TIMESTAMPTZ, resolved_by UUID REFERENCES auth.users(id));
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports(target_type, target_id);
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reports_insert" ON reports;
DROP POLICY IF EXISTS "reports_select_own" ON reports;
DROP POLICY IF EXISTS "reports_select_admin" ON reports;
DROP POLICY IF EXISTS "reports_update_admin" ON reports;
CREATE POLICY "reports_insert" ON reports FOR INSERT WITH CHECK (auth.uid() = reporter_id);
CREATE POLICY "reports_select_own" ON reports FOR SELECT USING (auth.uid() = reporter_id);
CREATE POLICY "reports_select_admin" ON reports FOR SELECT USING (is_admin());
CREATE POLICY "reports_update_admin" ON reports FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());

CREATE OR REPLACE FUNCTION get_reports_count() RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ BEGIN IF NOT is_admin() THEN RETURN 0; END IF; RETURN (SELECT COUNT(*)::BIGINT FROM reports WHERE status = 'pending'); END; $$;
GRANT EXECUTE ON FUNCTION get_reports_count() TO authenticated;

CREATE OR REPLACE FUNCTION create_report(p_target_type TEXT, p_target_id UUID, p_reason TEXT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_id UUID; BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF; IF p_target_type NOT IN ('post', 'comment') THEN RAISE EXCEPTION 'Недопустимый тип'; END IF; INSERT INTO reports (reporter_id, target_type, target_id, reason) VALUES (auth.uid(), p_target_type, p_target_id, p_reason) RETURNING id INTO v_id; RETURN v_id; END; $$;
GRANT EXECUTE ON FUNCTION create_report(TEXT, UUID, TEXT) TO authenticated;

CREATE TABLE IF NOT EXISTS user_blacklist (user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, blocked_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, blocked_user_id), CHECK (user_id != blocked_user_id));
CREATE INDEX IF NOT EXISTS idx_user_blacklist_user ON user_blacklist(user_id);
ALTER TABLE user_blacklist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "user_blacklist_select" ON user_blacklist;
DROP POLICY IF EXISTS "user_blacklist_insert" ON user_blacklist;
DROP POLICY IF EXISTS "user_blacklist_delete" ON user_blacklist;
CREATE POLICY "user_blacklist_select" ON user_blacklist FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_blacklist_insert" ON user_blacklist FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_blacklist_delete" ON user_blacklist FOR DELETE USING (auth.uid() = user_id);

-- Realtime для мгновенной доставки сообщений (если ошибка "already exists" — таблица уже в публикации, пропустите)
-- ALTER PUBLICATION supabase_realtime ADD TABLE messages;

-- Заполнить search_vector для существующих постов
UPDATE posts SET search_vector = setweight(to_tsvector('russian', coalesce(title, '')), 'A') || setweight(to_tsvector('russian', coalesce(body, '')), 'B') WHERE search_vector IS NULL;

-- ========== ГОТОВО ==========
