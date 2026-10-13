/// Bottom-navigation shell: Home · History · Browser · More.
///
/// The four primary surfaces live in an [IndexedStack] so each tab keeps
/// its scroll position, browser session and loaded data while the user
/// moves between them. A [NavigationBar] (Material 3) drives the stack
/// and handles bottom system-bar insets itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n/app_i18n.dart';
import '../features/browser/dapp_browser_screen.dart';
import '../features/history/history_screen.dart';
import '../features/more/more_screen.dart';
import '../features/wallet/dashboard_screen.dart';

/// Inherited handle for switching tabs programmatically (e.g. the
/// dashboard's "View all" activity link jumps to the History tab).
class HomeTabs extends InheritedWidget {
  /// Switches to the tab at [index] (0 = Home … 3 = More).
  final void Function(int index) goTo;

  /// Creates the scope.
  const HomeTabs({super.key, required this.goTo, required super.child});

  /// Returns the nearest scope, or null outside a [HomeShell].
  static HomeTabs? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeTabs>();

  @override
  bool updateShouldNotify(HomeTabs oldWidget) => false;
}

/// App shell with bottom navigation for a wallet that has accounts.
class HomeShell extends StatefulWidget {
  /// Creates the shell.
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _goTo(int index) {
    if (index == _index) return;
    // Light haptic on tab switch — standard M3 navigation feedback.
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return HomeTabs(
      goTo: _goTo,
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [
            DashboardScreen(),
            HistoryScreen(),
            DappBrowserScreen(),
            MoreScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: context.t('nav.home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: context.t('nav.history'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.public_outlined),
              selectedIcon: const Icon(Icons.public),
              label: context.t('nav.browser'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.apps),
              selectedIcon: const Icon(Icons.apps),
              label: context.t('nav.more'),
            ),
          ],
        ),
      ),
    );
  }
}
