-- Включить Realtime для таблицы messages (для мгновенной доставки сообщений)
-- Выполните в Supabase SQL Editor, если Realtime ещё не включён для messages

ALTER PUBLICATION supabase_realtime ADD TABLE messages;
