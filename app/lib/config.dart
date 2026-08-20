/// Supabase connection.
///
/// Values are injected at build time via `--dart-define` so the same source
/// works for local dev and a deployed build:
///
///   flutter build web \
///     --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=<publishable-or-anon-key>
///
/// With no `--dart-define`, it falls back to the local `supabase start` stack,
/// so `flutter run` keeps working unchanged. The anon/publishable key is a
/// public client key (safe to ship in a web build); it is not a secret.
class Config {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  );
}
