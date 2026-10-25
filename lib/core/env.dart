/// 環境設定。
///
/// ローカル開発では既定値（ローカル Supabase）を使う。
/// 本番や別環境では、起動時に --dart-define で上書きする:
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=xxxx
///
/// 注意:
/// - Web(Chrome)から接続する場合は 127.0.0.1 でOK。
/// - Android エミュレータからホストの Supabase に繋ぐ場合は
///   127.0.0.1 ではなく 10.0.2.2 を使う必要がある。
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );
}
