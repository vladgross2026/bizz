-- BizForum: таблицы для Supabase (PostgreSQL)
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run

-- Категории (фиксированный набор)
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

-- Посты
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

-- Комментарии
CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  author_name TEXT NOT NULL DEFAULT 'Гость',
  author_device_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);

-- Просмотры постов (один счётчик на пост)
CREATE TABLE IF NOT EXISTS post_views (
  post_id UUID PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
  view_count BIGINT NOT NULL DEFAULT 0
);

-- Реакции (один тип на пользователя на пост; типы: like, love, haha, fire, rocket, idea, handshake, sad, ugh, celebrate)
CREATE TABLE IF NOT EXISTS reactions (
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('like','useful','love','haha','fire','rocket','idea','handshake','sad','ugh','celebrate')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);
-- Если таблица уже создана с старым CHECK: ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_type_check; ALTER TABLE reactions ADD CONSTRAINT reactions_type_check CHECK (type IN ('like','useful','love','haha','fire','rocket','idea','handshake','sad','ugh','celebrate'));

-- Избранное (только для авторизованных)
CREATE TABLE IF NOT EXISTS favorites (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

-- Профили (имя, фамилия, компания, секретное слово; верификация — только админ вручную)
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

-- Заявки в друзья (знакомства)
CREATE TABLE IF NOT EXISTS friend_requests (
  from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (from_user_id, to_user_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_from ON friend_requests(from_user_id);

-- Индексы
CREATE INDEX IF NOT EXISTS idx_posts_category ON posts(category_id);
CREATE INDEX IF NOT EXISTS idx_posts_created ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comments_post ON comments(post_id);

-- RLS (Row Level Security)
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE friend_requests ENABLE ROW LEVEL SECURITY;

-- Заявки в друзья: вижу свои (отправленные и входящие); создаю от своего имени; обновлять статус может только получатель
CREATE POLICY "friend_requests_select" ON friend_requests FOR SELECT USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);
CREATE POLICY "friend_requests_insert" ON friend_requests FOR INSERT WITH CHECK (auth.uid() = from_user_id);
CREATE POLICY "friend_requests_update" ON friend_requests FOR UPDATE USING (auth.uid() = to_user_id);

-- Категории: чтение всем
CREATE POLICY "categories_select" ON categories FOR SELECT USING (true);

-- Посты: чтение всем; создание всем; изменение/удаление — автор
CREATE POLICY "posts_select" ON posts FOR SELECT USING (true);
CREATE POLICY "posts_insert" ON posts FOR INSERT WITH CHECK (true);
CREATE POLICY "posts_update" ON posts FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "posts_delete" ON posts FOR DELETE USING (auth.uid() = author_id);

-- Комментарии: чтение всем; создание всем; изменение/удаление — автор по author_id
CREATE POLICY "comments_select" ON comments FOR SELECT USING (true);
CREATE POLICY "comments_insert" ON comments FOR INSERT WITH CHECK (true);
CREATE POLICY "comments_update" ON comments FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "comments_delete" ON comments FOR DELETE USING (auth.uid() = author_id);

-- Просмотры: чтение всем; вставка/обновление — через функцию
CREATE POLICY "post_views_select" ON post_views FOR SELECT USING (true);
CREATE POLICY "post_views_all" ON post_views FOR ALL USING (true);

-- Реакции: чтение всем; вставка/обновление/удаление — свой user_id (смена типа = UPDATE)
CREATE POLICY "reactions_select" ON reactions FOR SELECT USING (true);
CREATE POLICY "reactions_insert" ON reactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "reactions_update" ON reactions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "reactions_delete" ON reactions FOR DELETE USING (auth.uid() = user_id);

-- Избранное: только свой список
CREATE POLICY "favorites_select" ON favorites FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "favorites_insert" ON favorites FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "favorites_delete" ON favorites FOR DELETE USING (auth.uid() = user_id);

-- Профили: только свой профиль (чтение, вставка при регистрации, обновление)
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "profiles_insert" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (auth.uid() = id);

-- Функция: увеличить счётчик просмотров
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

-- Владелец профиля не может сам себе поставить verified; админ может менять verified кому угодно
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
DROP TRIGGER IF EXISTS tr_profiles_verified ON profiles;
CREATE TRIGGER tr_profiles_verified BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION profiles_verified_only_by_admin();

-- Если таблица profiles уже была создана без новых полей, выполните в SQL Editor:
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS verified BOOLEAN NOT NULL DEFAULT false;
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS date_of_birth DATE;
-- Верификация аккаунта: в Supabase Dashboard → Table Editor → profiles → для пользователя установите verified = true.

-- Админ: только если secret_word = 'admingrosskremeshova'
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND secret_word = 'admingrosskremeshova'); $$;

CREATE OR REPLACE FUNCTION admin_list_profiles()
RETURNS SETOF profiles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  RETURN QUERY SELECT * FROM profiles ORDER BY created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION admin_update_profile(p_id UUID, p_first_name TEXT, p_last_name TEXT, p_company TEXT, p_verified BOOLEAN)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  UPDATE profiles SET first_name = COALESCE(p_first_name, first_name), last_name = COALESCE(p_last_name, last_name), company = COALESCE(p_company, company), verified = COALESCE(p_verified, verified), updated_at = now() WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_comment(p_comment_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN IF is_admin() THEN DELETE FROM comments WHERE id = p_comment_id; END IF; END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_post(p_post_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN IF is_admin() THEN DELETE FROM posts WHERE id = p_post_id; END IF; END;
$$;

CREATE OR REPLACE FUNCTION admin_update_post(p_post_id UUID, p_title TEXT, p_body TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  UPDATE posts SET title = COALESCE(p_title, title), body = COALESCE(p_body, body) WHERE id = p_post_id;
END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_profile(p_user_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  DELETE FROM profiles WHERE id = p_user_id;
END;
$$;

-- Поиск профилей для знакомств (по имени/фамилии; только верифицированные; без себя)
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

GRANT EXECUTE ON FUNCTION admin_list_profiles() TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_profile(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_comment(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_post(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_post(UUID, TEXT, TEXT) TO authenticated;

-- Тестовые посты не создаём — посты пишут верифицированные пользователи через «Новый пост».
