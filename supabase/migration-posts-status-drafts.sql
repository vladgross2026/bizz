-- Черновики постов: колонка status в posts
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run

ALTER TABLE posts ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published';
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_status_check;
ALTER TABLE posts ADD CONSTRAINT posts_status_check CHECK (status IN ('draft', 'published'));

-- RLS: убедитесь, что SELECT по posts разрешён для (status = 'published' OR author_id = auth.uid()).
-- Иначе создайте политику или отредактируйте существующую для posts.
