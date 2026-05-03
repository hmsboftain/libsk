import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../pages/home_page.dart';
import '../pages/boutiques_page.dart';
import '../pages/orders_page.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class MainNavigationPage extends StatefulWidget {
  final Function(Locale) onLanguageChange;

  const MainNavigationPage({
    super.key,
    required this.onLanguageChange,
  });

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage>
    with WidgetsBindingObserver {
  int currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FirestoreService.setCurrentUserOnline();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FirestoreService.setCurrentUserOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FirestoreService.setCurrentUserOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      FirestoreService.setCurrentUserOffline();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const HomePage(),
      const BoutiquesPage(),
      const OrdersPage(),
    ];

    return Scaffold(
      body: pages[currentPageIndex],
      bottomNavigationBar: NavigationBar(
        height: 70,
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.softAccent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: currentPageIndex,
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            selectedIcon: const Icon(Icons.home),
            icon: const Icon(Icons.home_outlined),
            label: AppLocalizations.of(context)!.home,
          ),
          NavigationDestination(
            selectedIcon: const Icon(Icons.checkroom),
            icon: const Icon(Icons.checkroom_outlined),
            label: AppLocalizations.of(context)!.boutiques,
          ),
          NavigationDestination(
            selectedIcon: const Icon(Icons.receipt_long),
            icon: const Icon(Icons.receipt_long_outlined),
            label: AppLocalizations.of(context)!.orders,
          ),
        ],
      ),
    );
  }
}