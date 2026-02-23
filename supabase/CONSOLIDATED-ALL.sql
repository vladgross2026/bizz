-- =============================================================================
-- СВОДНАЯ МИГРАЦИЯ — всё необходимое в одном файле
-- Скопируйте в Supabase SQL Editor и выполните Run
-- Повторный запуск безопасен (IF NOT EXISTS, DROP IF EXISTS)
-- =============================================================================

-- 1. Функция is_admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE
AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND secret_word = 'admingrosskremeshova'); $$;

-- 2. ТАБЛИЦА NOTIFICATIONS (обязательна до триггера на messages!)
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  payload JSONB DEFAULT '{}',
  read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notifications_select" ON notifications;
DROP POLICY IF EXISTS "notifications_update" ON notifications;
DROP POLICY IF EXISTS "notifications_insert" ON notifications;
CREATE POLICY "notifications_select" ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "notifications_insert" ON notifications FOR INSERT WITH CHECK (true);
CREATE POLICY "notifications_update" ON notifications FOR UPDATE USING (auth.uid() = user_id);

-- 3. Чаты: conversations, messages, participants (если ещё нет)
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL DEFAULT 'dm' CHECK (type IN ('dm', 'admin', 'ai', 'group')),
  title TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conversation_participants_select" ON conversation_participants;
CREATE POLICY "conversation_participants_select" ON conversation_participants FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "conversation_participants_insert" ON conversation_participants;
CREATE POLICY "conversation_participants_insert" ON conversation_participants FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "messages_select" ON messages;
CREATE POLICY "messages_select" ON messages FOR SELECT USING (
  EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = messages.conversation_id AND cp.user_id = auth.uid())
);
DROP POLICY IF EXISTS "messages_insert" ON messages;
CREATE POLICY "messages_insert" ON messages FOR INSERT WITH CHECK (
  sender_id = auth.uid() AND EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = messages.conversation_id AND cp.user_id = auth.uid())
);

-- 4. Админ-чат: RPC и триггер уведомлений
CREATE OR REPLACE FUNCTION create_or_get_admin_conversation(p_user_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cid UUID;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN RAISE EXCEPTION 'Только владелец может создавать свой admin-диалог'; END IF;
  SELECT c.id INTO v_cid FROM conversations c JOIN conversation_participants cp ON cp.conversation_id = c.id WHERE c.type = 'admin' AND cp.user_id = p_user_id LIMIT 1;
  IF v_cid IS NOT NULL THEN RETURN v_cid; END IF;
  INSERT INTO conversations (type) VALUES ('admin') RETURNING id INTO v_cid;
  INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, p_user_id);
  RETURN v_cid;
END;
$$;
GRANT EXECUTE ON FUNCTION create_or_get_admin_conversation(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION get_admin_conversations_list()
RETURNS TABLE(conversation_id UUID, user_id UUID, user_name TEXT, last_body TEXT, last_created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  RETURN QUERY SELECT c.id, cp.user_id, TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')) AS user_name, m.body AS last_body, m.created_at AS last_created_at
  FROM conversations c JOIN conversation_participants cp ON cp.conversation_id = c.id
  LEFT JOIN profiles p ON p.id = cp.user_id
  LEFT JOIN LATERAL (SELECT body, created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1) m ON true
  WHERE c.type = 'admin' ORDER BY m.created_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_admin_conversations_list() TO authenticated;

CREATE OR REPLACE FUNCTION admin_send_message(p_conv_id UUID, p_body TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_msg_id UUID;
BEGIN
  IF NOT is_admin() OR p_body IS NULL OR trim(p_body) = '' THEN RAISE EXCEPTION 'Доступ запрещён'; END IF;
  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conv_id AND type = 'admin') THEN RAISE EXCEPTION 'Диалог не найден'; END IF;
  INSERT INTO messages (conversation_id, sender_id, body) VALUES (p_conv_id, auth.uid(), trim(p_body)) RETURNING id INTO v_msg_id;
  RETURN v_msg_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_send_message(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION admin_get_messages(p_conv_id UUID)
RETURNS TABLE(msg_id UUID, sender_id UUID, body TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conv_id AND type = 'admin') THEN RETURN; END IF;
  RETURN QUERY SELECT m.id, m.sender_id, m.body, m.created_at FROM messages m WHERE m.conversation_id = p_conv_id ORDER BY m.created_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_get_messages(UUID) TO authenticated;

-- Триггер: пользователь пишет админу → админ получает уведомление
CREATE OR REPLACE FUNCTION notify_on_admin_chat_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_conv_type TEXT; v_sender_is_admin BOOLEAN; r RECORD;
BEGIN
  SELECT c.type INTO v_conv_type FROM conversations c WHERE c.id = NEW.conversation_id;
  IF v_conv_type IS NULL OR v_conv_type != 'admin' THEN RETURN NEW; END IF;
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = NEW.sender_id AND secret_word = 'admingrosskremeshova') INTO v_sender_is_admin;
  IF v_sender_is_admin THEN
    FOR r IN SELECT cp.user_id FROM conversation_participants cp WHERE cp.conversation_id = NEW.conversation_id AND cp.user_id != NEW.sender_id LOOP
      INSERT INTO notifications (user_id, type, payload, read) VALUES (r.user_id, 'message_reply', jsonb_build_object('conversation_id', NEW.conversation_id, 'from_user_id', NEW.sender_id, 'message_id', NEW.id), false);
    END LOOP;
  ELSE
    FOR r IN SELECT id FROM profiles WHERE secret_word = 'admingrosskremeshova' AND id != NEW.sender_id LOOP
      INSERT INTO notifications (user_id, type, payload, read) VALUES (r.id, 'message_reply', jsonb_build_object('conversation_id', NEW.conversation_id, 'from_user_id', NEW.sender_id, 'message_id', NEW.id), false);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS tr_notify_on_admin_chat ON messages;
CREATE TRIGGER tr_notify_on_admin_chat AFTER INSERT ON messages FOR EACH ROW EXECUTE FUNCTION notify_on_admin_chat_message();

-- 5. create_dm_conversation
CREATE OR REPLACE FUNCTION create_dm_conversation(p_other_user_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_cid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
  IF p_other_user_id = v_uid THEN RAISE EXCEPTION 'Нельзя создать чат с самим собой'; END IF;
  SELECT c.id INTO v_cid FROM conversations c JOIN conversation_participants cp1 ON cp1.conversation_id = c.id AND cp1.user_id = v_uid
  JOIN conversation_participants cp2 ON cp2.conversation_id = c.id AND cp2.user_id = p_other_user_id WHERE c.type = 'dm' ORDER BY c.created_at ASC LIMIT 1;
  IF v_cid IS NOT NULL THEN RETURN v_cid; END IF;
  INSERT INTO conversations (type) VALUES ('dm') RETURNING id INTO v_cid;
  INSERT INTO conversation_participants (conversation_id, user_id) VALUES (v_cid, v_uid), (v_cid, p_other_user_id);
  RETURN v_cid;
END;
$$;
GRANT EXECUTE ON FUNCTION create_dm_conversation(UUID) TO authenticated;

-- 6. Подписки
CREATE TABLE IF NOT EXISTS subscriptions (user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, author_id), CHECK (user_id != author_id));
CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id);
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "subscriptions_select" ON subscriptions;
DROP POLICY IF EXISTS "subscriptions_insert" ON subscriptions;
DROP POLICY IF EXISTS "subscriptions_delete" ON subscriptions;
CREATE POLICY "subscriptions_select" ON subscriptions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "subscriptions_insert" ON subscriptions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "subscriptions_delete" ON subscriptions FOR DELETE USING (auth.uid() = user_id);

-- 7. profiles: company_stage, balance
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS company_stage TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS balance INTEGER NOT NULL DEFAULT 0;

-- 8. posts: status, price
ALTER TABLE posts ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published';
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_status_check;
ALTER TABLE posts ADD CONSTRAINT posts_status_check CHECK (status IN ('draft', 'published'));
ALTER TABLE posts ADD COLUMN IF NOT EXISTS price INTEGER;
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_price_non_negative;
ALTER TABLE posts ADD CONSTRAINT posts_price_non_negative CHECK (price IS NULL OR price >= 0);

-- 9. Категория «Полезное»
INSERT INTO categories (id, name, slug) VALUES ('useful', 'Полезное', 'useful') ON CONFLICT (id) DO NOTHING;

-- 10. Покупки постов, buy_post
CREATE TABLE IF NOT EXISTS post_purchases (user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE, amount INTEGER NOT NULL CHECK (amount > 0), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, post_id));
CREATE INDEX IF NOT EXISTS idx_post_purchases_user ON post_purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_post_purchases_post ON post_purchases(post_id);
ALTER TABLE post_purchases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "post_purchases_select" ON post_purchases;
DROP POLICY IF EXISTS "post_purchases_insert" ON post_purchases;
CREATE POLICY "post_purchases_select" ON post_purchases FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "post_purchases_insert" ON post_purchases FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION buy_post(p_post_id UUID) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_price INTEGER; v_author_id UUID; v_buyer_bal INTEGER; v_author_bal INTEGER;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF;
  SELECT p.price, p.author_id INTO v_price, v_author_id FROM posts p WHERE p.id = p_post_id AND p.status = 'published';
  IF v_price IS NULL OR v_price <= 0 THEN RAISE EXCEPTION 'Пост не платный'; END IF;
  IF v_author_id = v_uid THEN RAISE EXCEPTION 'Нельзя купить свой пост'; END IF;
  IF EXISTS (SELECT 1 FROM post_purchases WHERE user_id = v_uid AND post_id = p_post_id) THEN RAISE EXCEPTION 'Вы уже купили этот пост'; END IF;
  SELECT COALESCE(balance, 0) INTO v_buyer_bal FROM profiles WHERE id = v_uid;
  IF v_buyer_bal < v_price THEN RAISE EXCEPTION 'Недостаточно средств'; END IF;
  SELECT COALESCE(balance, 0) INTO v_author_bal FROM profiles WHERE id = v_author_id;
  UPDATE profiles SET balance = balance - v_price, updated_at = now() WHERE id = v_uid;
  UPDATE profiles SET balance = balance + v_price, updated_at = now() WHERE id = v_author_id;
  INSERT INTO post_purchases (user_id, post_id, amount) VALUES (v_uid, p_post_id, v_price);
END;
$$;
GRANT EXECUTE ON FUNCTION buy_post(UUID) TO authenticated;

-- 11. admin_add_balance, admin_update_profile с p_balance
CREATE OR REPLACE FUNCTION admin_add_balance(p_user_id UUID, p_amount INTEGER) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN IF NOT is_admin() THEN RAISE EXCEPTION 'Доступ запрещён'; END IF; IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Сумма должна быть положительной'; END IF; UPDATE profiles SET balance = COALESCE(balance, 0) + p_amount, updated_at = now() WHERE id = p_user_id; END;
$$;
GRANT EXECUTE ON FUNCTION admin_add_balance(UUID, INTEGER) TO authenticated;

DROP FUNCTION IF EXISTS admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT);
CREATE OR REPLACE FUNCTION admin_update_profile(p_id UUID, p_first_name TEXT, p_last_name TEXT, p_company TEXT, p_verified BOOLEAN, p_company_stage TEXT DEFAULT NULL, p_balance INTEGER DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RETURN; END IF;
  UPDATE profiles SET first_name = COALESCE(p_first_name, first_name), last_name = COALESCE(p_last_name, last_name), company = COALESCE(p_company, company), verified = COALESCE(p_verified, verified), company_stage = COALESCE(p_company_stage, company_stage), balance = CASE WHEN p_balance IS NOT NULL THEN p_balance ELSE balance END, updated_at = now() WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_update_profile(UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER) TO authenticated;

-- 12. Подсчёт подписчиков
CREATE OR REPLACE FUNCTION get_subscriber_count(p_author_id UUID) RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$ SELECT count(*)::int FROM subscriptions WHERE author_id = p_author_id; $$;
GRANT EXECUTE ON FUNCTION get_subscriber_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_subscriber_count(UUID) TO anon;

-- Готово. После Run все таблицы и функции будут на месте.
