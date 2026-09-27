import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class SupabaseClientManager {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static Future<bool> verifyConnection() async {
    try {
      await client.from('profiles').select('id').limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }
}
