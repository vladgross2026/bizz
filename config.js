// BizForum — подключение к Supabase (ключи из Project Settings → API)
// requireEmailConfirmation: false — вход без подтверждения почты. Когда понадобятся письма — true + Supabase Auth → Email → Confirm email.
window.BIZFORUM_CONFIG = {
  useSupabase: true,
  requireEmailConfirmation: false,
  SUPABASE_URL: 'https://qddnggibzszezajemaua.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkZG5nZ2lienN6ZXphamVtYXVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA1NDE3MzgsImV4cCI6MjA4NjExNzczOH0.erEm1QH0VHbhTqFHkbwdptk-xq8EEril1yTj27S6dEc'
};
