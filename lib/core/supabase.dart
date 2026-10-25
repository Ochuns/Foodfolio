import 'package:supabase_flutter/supabase_flutter.dart';

/// アプリ全体で使う Supabase クライアントへのショートカット。
/// 例: `await supabase.from('restaurants').select()`
SupabaseClient get supabase => Supabase.instance.client;
