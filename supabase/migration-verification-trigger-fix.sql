-- Исправление триггера: админ может одобрять верификацию (установить verified = true)
-- Выполните в Supabase SQL Editor, если кнопки «Одобрить»/«Отклонить» не срабатывают

CREATE OR REPLACE FUNCTION profiles_verified_only_by_admin()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.verified IS DISTINCT FROM OLD.verified AND auth.uid() = OLD.id AND NOT is_admin() THEN
    NEW.verified := OLD.verified;
  END IF;
  RETURN NEW;
END;
$$;
