import 'package:flutter/material.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final theme = ThemeController();
  await theme.load(); // so the first frame already has the saved colors
  runApp(MyApp(theme));
}

class MyApp extends StatelessWidget {
  final ThemeController theme;
  const MyApp(this.theme, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: theme,
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.themeFor(Brightness.light),
          darkTheme: theme.themeFor(Brightness.dark),
          themeMode: theme.mode,
          home: AppShell(theme: theme),
        ),
      );
}
