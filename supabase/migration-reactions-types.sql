-- Обновление типов реакций под новый набор (мужик!, королева!, ржаакаа, огонь, фу, грустно, делаем бабки, хахаха)
-- Выполните в Supabase: SQL Editor → New query → вставьте и Run

ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_type_check;
ALTER TABLE reactions ADD CONSTRAINT reactions_type_check
  CHECK (type IN ('muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha'));
