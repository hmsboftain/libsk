import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../pages/home_page.dart';
import '../pages/boutiques_page.dart';
import '../pages/orders_page.dart';
import '../pages/category_browse_page.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class MainNavigationPage extends StatefulWidget {
  final Function(Locale) onLanguageChange;

  const MainNavigationPage({super.key, required this.onLanguageChange});

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
      const CategoryBrowsePage(),
      const OrdersPage(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: pages[currentPageIndex],
      bottomNavigationBar: NavigationBar(
        height: 70,
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        indicatorColor: AppColors.selectedSoft,
        shadowColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: currentPageIndex,
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            selectedIcon: const Icon(Icons.home, color: AppColors.primaryText),
            icon: const Icon(Icons.home_outlined, color: AppColors.softAccent),
            label: AppLocalizations.of(context)!.home,
          ),
          NavigationDestination(
            selectedIcon: const Icon(
              Icons.checkroom,
              color: AppColors.primaryText,
            ),
            icon: const Icon(
              Icons.checkroom_outlined,
              color: AppColors.softAccent,
            ),
            label: AppLocalizations.of(context)!.boutiques,
          ),
          NavigationDestination(
            selectedIcon: const Icon(
              Icons.grid_view,
              color: AppColors.primaryText,
            ),
            icon: const Icon(
              Icons.grid_view_outlined,
              color: AppColors.softAccent,
            ),
            label: 'Browse',
          ),
          NavigationDestination(
            selectedIcon: const Icon(
              Icons.receipt_long,
              color: AppColors.primaryText,
            ),
            icon: const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.softAccent,
            ),
            label: AppLocalizations.of(context)!.orders,
          ),
        ],
      ),
    );
  }
}
