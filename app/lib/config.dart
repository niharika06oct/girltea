/// Local Supabase connection (printed by `supabase start`).
/// For a real build these move to --dart-define / env, but for the
/// local dev slice the anon key is safe to inline.
class Config {
  static const supabaseUrl = 'http://127.0.0.1:54321';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
}
