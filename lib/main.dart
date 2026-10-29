import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'core/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    // レガシー形式(JWT)の anon key も受け付けるため anonKey を使用
    // ignore: deprecated_member_use
    anonKey: Env.supabaseAnonKey,
  );

  runApp(const FoodfolioApp());
}

class FoodfolioApp extends StatelessWidget {
  const FoodfolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Foodfolio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
        // ヘッダー（AppBar）を辞典テーマの茶色に統一（フッターと同じ配色）
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4A3526),
          foregroundColor: Color(0xFFF3ECDD),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 2,
          shadowColor: Colors.black54,
          titleTextStyle: TextStyle(
            color: Color(0xFFF3ECDD),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
