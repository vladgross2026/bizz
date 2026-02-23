-- Исправление RLS: участники видят всех в своих чатах (для поиска общего DM)
-- Без этого getOrCreateDmConversation не находит общий диалог и создаёт новый каждый раз
-- Выполните в Supabase SQL Editor

DROP POLICY IF EXISTS "conversation_participants_select" ON conversation_participants;
CREATE POLICY "conversation_participants_select" ON conversation_participants FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM conversation_participants cp2
    WHERE cp2.conversation_id = conversation_participants.conversation_id
    AND cp2.user_id = auth.uid()
  )
);
