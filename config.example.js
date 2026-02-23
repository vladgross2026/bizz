// Скопируйте в config.js и подставьте данные из Supabase (Project Settings → API).
// Пока config.js нет или useSupabase: false — сайт работает на localStorage и мок-данных.
// requireEmailConfirmation: false — вход без подтверждения почты (включите true и в Supabase Auth → Email → Confirm email, когда понадобятся письма).
window.BIZFORUM_CONFIG = {
  useSupabase: false,
  requireEmailConfirmation: false,
  SUPABASE_URL: 'https://XXXXX.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
};
