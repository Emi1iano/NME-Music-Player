import 'package:flutter/material.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const NmeApp());
}

class NmeApp extends StatelessWidget {
  const NmeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NME',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}
