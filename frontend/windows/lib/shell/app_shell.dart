import 'package:flutter/material.dart';
import '../screens/library_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/sync_settings_screen.dart';
import '../services/store.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/glass.dart';
import '../widgets/transport_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final store = Store();
  int index = 0;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: [
            const Backdrop(),
            SafeArea(
              child: LayoutBuilder(builder: (_, box) {
                final wide = box.maxWidth > 800;
                final pages = IndexedStack(index: index, children: [
                  LibraryScreen(store),
                  PlaylistsScreen(store),
                  StatsScreen(store),
                  SyncSettingsScreen(store),
                ]);
                final content = Column(children: [
                  Expanded(child: pages),
                  if (store.playing != null) ...[const SizedBox(height: 14), TransportBar(store)],
                ]);
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: wide
                      ? Row(children: [
                          SizedBox(
                            width: 230,
                            child: AppSidebar(index: index, onTap: (i) => setState(() => index = i), store: store),
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: content),
                        ])
                      : Column(children: [
                          Expanded(child: content),
                          const SizedBox(height: 14),
                          AppDock(index: index, onTap: (i) => setState(() => index = i)),
                        ]),
                );
              }),
            ),
          ]),
        ),
      );
}
