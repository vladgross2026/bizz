-- Выполнить в Supabase: SQL Editor → New query → вставить и Run
-- Комментарии: включаем RLS и разрешаем вставку всем (гости и авторизованные).

ALTER TABLE comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "comments_insert" ON comments;
CREATE POLICY "comments_insert" ON comments
  FOR INSERT WITH CHECK (true);

-- Убедиться, что чтение тоже разрешено
DROP POLICY IF EXISTS "comments_select" ON comments;
CREATE POLICY "comments_select" ON comments
  FOR SELECT USING (true);

-- После выполнения: на странице поста должна быть форма "Оставить комментарий" и кнопка Отправить.
-- Если при отправке появляется красное сообщение — скопируйте его (это текст ошибки от Supabase).
