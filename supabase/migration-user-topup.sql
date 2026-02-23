-- Пополнение баланса пользователем (демо, без платёжки)
CREATE OR REPLACE FUNCTION user_topup_balance(p_amount INTEGER) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ DECLARE v_uid UUID := auth.uid(); BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Не авторизован'; END IF; IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Сумма должна быть положительной'; END IF; UPDATE profiles SET balance = COALESCE(balance, 0) + p_amount, updated_at = now() WHERE id = v_uid; END; $$;
GRANT EXECUTE ON FUNCTION user_topup_balance(INTEGER) TO authenticated;
