-- Статистика и активность для панели администратора
-- Выполните в Supabase SQL Editor

CREATE OR REPLACE FUNCTION get_admin_stats()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE
  v_users BIGINT;
  v_posts BIGINT;
  v_comments BIGINT;
  v_unverified BIGINT;
  v_reports_pending BIGINT;
  v_admin_threads BIGINT;
  v_new_today BIGINT;
BEGIN
  IF NOT is_admin() THEN RETURN '{}'::JSONB; END IF;
  SELECT COUNT(*) INTO v_users FROM profiles;
  SELECT COUNT(*) INTO v_posts FROM posts WHERE status = 'published';
  SELECT COUNT(*) INTO v_comments FROM comments;
  SELECT COUNT(*) INTO v_unverified FROM profiles WHERE verified = false;
  SELECT COUNT(*) INTO v_reports_pending FROM reports WHERE status = 'pending';
  SELECT COUNT(*) INTO v_admin_threads FROM conversations WHERE type = 'admin';
  SELECT COUNT(*) INTO v_new_today FROM profiles WHERE created_at >= current_date;
  RETURN jsonb_build_object(
    'users', v_users,
    'posts', v_posts,
    'comments', v_comments,
    'unverified', v_unverified,
    'reportsPending', v_reports_pending,
    'adminThreads', v_admin_threads,
    'newToday', v_new_today
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_admin_stats() TO authenticated;

-- Последняя активность: новые регистрации и посты
CREATE OR REPLACE FUNCTION get_admin_recent_activity()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE
  v_recent_users JSONB;
  v_recent_posts JSONB;
BEGIN
  IF NOT is_admin() THEN RETURN '{"users":[],"posts":[]}'::JSONB; END IF;
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('id', p.id, 'name', TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), 'company', p.company, 'createdAt', p.created_at, 'verified', p.verified)
    ORDER BY p.created_at DESC
  ), '[]'::JSONB) INTO v_recent_users
  FROM (SELECT id, first_name, last_name, company, created_at, verified FROM profiles ORDER BY created_at DESC LIMIT 5) p;
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object('id', p.id, 'title', p.title, 'authorName', p.author_name, 'createdAt', p.created_at)
    ORDER BY p.created_at DESC
  ), '[]'::JSONB) INTO v_recent_posts
  FROM (SELECT id, title, author_name, created_at FROM posts WHERE status = 'published' ORDER BY created_at DESC LIMIT 5) p;
  RETURN jsonb_build_object('users', v_recent_users, 'posts', v_recent_posts);
END;
$$;
GRANT EXECUTE ON FUNCTION get_admin_recent_activity() TO authenticated;
