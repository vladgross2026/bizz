-- Уведомления админам при сообщении пользователя в админ-чат
-- Выполните в Supabase SQL Editor
-- Проблема: в admin-диалоге только пользователь в participants, админ не получал уведомления.

CREATE OR REPLACE FUNCTION notify_admins_on_admin_chat_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_conv_type TEXT;
  v_sender_is_admin BOOLEAN;
  r RECORD;
BEGIN
  SELECT c.type INTO v_conv_type FROM conversations c WHERE c.id = NEW.conversation_id;
  IF v_conv_type IS NULL OR v_conv_type != 'admin' THEN
    RETURN NEW;
  END IF;
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = NEW.sender_id AND secret_word = 'admingrosskremeshova') INTO v_sender_is_admin;
  IF v_sender_is_admin THEN
    RETURN NEW;
  END IF;
  FOR r IN SELECT id FROM profiles WHERE secret_word = 'admingrosskremeshova' AND id != NEW.sender_id
  LOOP
    INSERT INTO notifications (user_id, type, payload, read)
    VALUES (r.id, 'message_reply', jsonb_build_object('conversation_id', NEW.conversation_id, 'from_user_id', NEW.sender_id, 'message_id', NEW.id), false);
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_notify_admins_on_admin_chat ON messages;
CREATE TRIGGER tr_notify_admins_on_admin_chat
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_admins_on_admin_chat_message();
