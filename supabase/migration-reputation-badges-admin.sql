-- Репутация, бейджи, админ: лучший ответ
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run

-- 1. Реакция "полезно" на комментариях (для репутации)
ALTER TABLE comment_reactions DROP CONSTRAINT IF EXISTS comment_reactions_type_check;
ALTER TABLE comment_reactions ADD CONSTRAINT comment_reactions_type_check
  CHECK (type IN ('muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha','useful'));

-- 2. Этап компании в профиле (для бейджа «стартап 1–3 года» и т.п.)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS company_stage TEXT
  CHECK (company_stage IS NULL OR company_stage IN ('idea','startup_1_3','startup_3_5','growth','enterprise','other'));

-- 3. Таблица бейджей
CREATE TABLE IF NOT EXISTS badges (
  id TEXT PRIMARY KEY,
  name_ru TEXT NOT NULL,
  description_ru TEXT,
  icon TEXT,
  rule_type TEXT NOT NULL DEFAULT 'computed' CHECK (rule_type IN ('computed','assigned'))
);

INSERT INTO badges (id, name_ru, description_ru, rule_type) VALUES
  ('helped_10', 'Помог 10 раз', '10+ полезных ответов', 'computed'),
  ('helped_50', 'Помог 50 раз', '50+ полезных ответов', 'computed'),
  ('helped_100', 'Помог 100 раз', '100+ полезных ответов', 'computed'),
  ('startup_1_3', 'Стартап 1–3 года', 'Компания на этапе 1–3 года', 'computed'),
  ('startup_3_5', 'Стартап 3–5 лет', 'Компания на этапе 3–5 лет', 'computed'),
  ('expert_marketing', 'Эксперт по маркетингу', 'Активность в категории Маркетинг', 'computed'),
  ('expert_finance', 'Эксперт по финансам', 'Активность в категории Финансы', 'computed'),
  ('expert_sales', 'Эксперт по продажам', 'Активность в категории Продажи', 'computed')
ON CONFLICT (id) DO NOTHING;

-- 4. Связь пользователь — бейджи (вычисляемые и назначаемые)
CREATE TABLE IF NOT EXISTS user_badges (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_id TEXT NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, badge_id)
);
CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);

ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "user_badges_select" ON user_badges;
CREATE POLICY "user_badges_select" ON user_badges FOR SELECT USING (true);
DROP POLICY IF EXISTS "user_badges_admin" ON user_badges;
CREATE POLICY "user_badges_insert" ON user_badges FOR INSERT WITH CHECK (is_admin());
CREATE POLICY "user_badges_delete" ON user_badges FOR DELETE USING (is_admin());

-- 5. Админ может отметить лучший ответ (автор поста или модератор)
CREATE OR REPLACE FUNCTION admin_set_best_answer(p_post_id UUID, p_comment_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  UPDATE posts SET best_answer_comment_id = p_comment_id WHERE id = p_post_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_set_best_answer(UUID, UUID) TO authenticated;

-- 6. Функция: получить бейджи пользователя (назначенные + вычисляемые по helpfulCount и company_stage)
CREATE OR REPLACE FUNCTION get_user_badges(p_user_id UUID)
RETURNS TABLE(badge_id TEXT, name_ru TEXT, description_ru TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE
AS $$
DECLARE helpful_cnt BIGINT;
DECLARE stage TEXT;
BEGIN
  SELECT pr.company_stage INTO stage FROM profiles pr WHERE pr.id = p_user_id;
  SELECT COUNT(DISTINCT cr.comment_id) INTO helpful_cnt FROM comments c
    JOIN comment_reactions cr ON cr.comment_id = c.id AND cr.type = 'useful'
    WHERE c.author_id = p_user_id;
  RETURN QUERY SELECT ub.badge_id, b.name_ru, b.description_ru FROM user_badges ub JOIN badges b ON b.id = ub.badge_id WHERE ub.user_id = p_user_id;
  IF helpful_cnt >= 100 THEN RETURN QUERY SELECT 'helped_100'::TEXT, 'Помог 100 раз'::TEXT, '100+ полезных ответов'::TEXT; END IF;
  IF helpful_cnt >= 50 THEN RETURN QUERY SELECT 'helped_50'::TEXT, 'Помог 50 раз'::TEXT, '50+ полезных ответов'::TEXT; END IF;
  IF helpful_cnt >= 10 THEN RETURN QUERY SELECT 'helped_10'::TEXT, 'Помог 10 раз'::TEXT, '10+ полезных ответов'::TEXT; END IF;
  IF stage = 'startup_1_3' THEN RETURN QUERY SELECT 'startup_1_3'::TEXT, 'Стартап 1–3 года'::TEXT, 'Компания на этапе 1–3 года'::TEXT; END IF;
  IF stage = 'startup_3_5' THEN RETURN QUERY SELECT 'startup_3_5'::TEXT, 'Стартап 3–5 лет'::TEXT, 'Компания на этапе 3–5 лет'::TEXT; END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION get_user_badges(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_badges(UUID) TO anon;

-- 7. admin_update_profile: добавить company_stage
DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION admin_update_profile(p_id UUID, p_first_name TEXT, p_last_name TEXT, p_company TEXT, p_verified BOOLEAN, p_company_stage TEXT DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  UPDATE profiles SET
    first_name = COALESCE(p_first_name, first_name),
    last_name = COALESCE(p_last_name, last_name),
    company = COALESCE(p_company, company),
    verified = COALESCE(p_verified, verified),
    company_stage = COALESCE(p_company_stage, company_stage),
    updated_at = now()
  WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT) TO authenticated;
