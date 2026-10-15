import 'package:flutter/material.dart';

import 'pages/splash_page.dart';

void main() {
  runApp(const IAppDecoderApp());
}

class IAppDecoderApp extends StatelessWidget {
  const IAppDecoderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iAppDecoder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4FC1E9),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const SplashPage(),
    );
  }
}
