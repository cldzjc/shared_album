import 'package:flutter/material.dart';

import 'pages/create_page.dart';
import 'pages/home_page.dart';
import 'pages/join_page.dart';
import 'pages/album_detail_page.dart';
import 'pages/login_page.dart';
import 'providers/join_album_provider.dart';

class SharedAlbumApp extends StatelessWidget {
  const SharedAlbumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shared Album',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        // 统一转场为 FadeForwards（淡入 + 微前移，iOS 16 风格）：
        // 1. 预览页磨砂背景不再从右侧滑入，与照片 Hero 展开动画统一；
        // 2. 避免 iOS Safari 边缘右滑返回时横向转场动画被中断导致的异常。
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
          },
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/create': (context) => const CreatePage(),
        '/join': (context) => const JoinPage(),
        '/login': (context) => const LoginPage(),
        '/album_detail': (context) {
          final album =
              ModalRoute.of(context)!.settings.arguments as AlbumModel;
          return AlbumDetailPage(album: album);
        },
      },
    );
  }
}
