import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/supabase_client_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局异常日志：便于定位 iOS 边缘右滑等平台性白屏问题的报错堆栈
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[App Error] ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[Platform Error] $error\n$stack');
    return true;
  };

  await SupabaseClientManager.initialize();

  runApp(
    // 🔴 必须用 ProviderScope 包裹，否则页面和管家（Provider）之间无法通信
    const ProviderScope(child: SharedAlbumApp()),
  );
}
