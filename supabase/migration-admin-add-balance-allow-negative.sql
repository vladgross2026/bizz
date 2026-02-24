-- Разрешить отрицательную сумму в «Добавить валюту»: -50 списывает с баланса.
CREATE OR REPLACE FUNCTION admin_add_balance(p_user_id UUID, p_amount INTEGER) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Доступ запрещён'; END IF;
  IF p_amount IS NULL OR p_amount = 0 THEN RAISE EXCEPTION 'Сумма не должна быть нулевой (положительная — пополнение, отрицательная — списание)'; END IF;
  UPDATE profiles SET balance = COALESCE(balance, 0) + p_amount, updated_at = now() WHERE id = p_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_add_balance(UUID, INTEGER) TO authenticated;
