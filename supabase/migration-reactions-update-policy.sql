-- Разрешить пользователю менять свою реакцию (старая подменяется новой)
-- Без этой политики upsert при смене типа реакции блокировался RLS (был только INSERT, не UPDATE).

CREATE POLICY "reactions_update" ON reactions
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
