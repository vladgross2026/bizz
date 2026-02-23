-- Добавить колонку parent_id в comments (для ответов на комментарии)
-- Выполните в Supabase SQL Editor, если нужны ответы на комментарии

ALTER TABLE comments ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES comments(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id) WHERE parent_id IS NOT NULL;
