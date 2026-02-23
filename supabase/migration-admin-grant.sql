-- Выдать права администратора пользователю (редактирование любых постов, реестр, верификация)
-- В Supabase: SQL Editor → замените YOUR_USER_ID на UUID вашего пользователя (Auth → Users → скопировать id)
-- Затем выполните запрос.

-- Вариант 1: вы знаете свой user id (из Auth → Users в Supabase)
-- UPDATE profiles SET secret_word = 'admingrosskremeshova' WHERE id = 'YOUR_USER_ID';

-- Вариант 2: выдать по email (подставьте свой email)
-- UPDATE profiles SET secret_word = 'admingrosskremeshova' WHERE id = (SELECT id FROM auth.users WHERE email = 'admin@example.com' LIMIT 1);

-- Проверка: функция is_admin() возвращает true, если у профиля secret_word = 'admingrosskremeshova'.
-- Тогда admin_update_post и admin_delete_post позволяют редактировать и удалять любые посты.
