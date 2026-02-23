-- Реакции на комментариях и поле "лучший ответ" на пост
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run

-- 1. Реакции на комментариях (типы как у постов)
CREATE TABLE IF NOT EXISTS comment_reactions (
  comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_comment_reactions_comment ON comment_reactions(comment_id);

ALTER TABLE comment_reactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "comment_reactions_select" ON comment_reactions FOR SELECT USING (true);
CREATE POLICY "comment_reactions_insert" ON comment_reactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "comment_reactions_delete" ON comment_reactions FOR DELETE USING (auth.uid() = user_id);

-- 2. Лучший ответ (автор поста может отметить один комментарий)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS best_answer_comment_id UUID REFERENCES comments(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_posts_best_answer ON posts(best_answer_comment_id) WHERE best_answer_comment_id IS NOT NULL;
