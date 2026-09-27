// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:shared_album/app.dart';
import 'package:shared_album/config/app_config.dart';

void main() {
  testWidgets('home page shows create and join buttons', (
    WidgetTester tester,
  ) async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );

    await tester.pumpWidget(const SharedAlbumApp());

    expect(find.text('创建'), findsOneWidget);
    expect(find.text('加入'), findsOneWidget);
  });
}
