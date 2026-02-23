-- Добавить категорию "Житейское"
INSERT INTO categories (id, name, slug) VALUES
  ('everyday', 'Житейское', 'everyday')
ON CONFLICT (id) DO NOTHING;
