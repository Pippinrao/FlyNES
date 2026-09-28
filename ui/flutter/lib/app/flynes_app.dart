import 'package:flutter/material.dart';

import '../design_system/app_theme.dart';
import '../features/foundation/foundation_page.dart';

class FlynesApp extends StatelessWidget {
  const FlynesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FlyNES',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: const FoundationPage(),
  );
}
