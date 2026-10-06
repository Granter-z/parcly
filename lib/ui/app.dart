import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/home/home_screen.dart';

class PickupApp extends StatelessWidget {
  const PickupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '待取件',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}