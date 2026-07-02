import 'package:flutter/material.dart';
import '../pages/home_page.dart';
import '../pages/boutiques_page.dart';
import '../pages/category_browse_page.dart';
import '../pages/orders_page.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

// Ink — warmer near-black used for active nav icons (vs pure-black primaryText).
const Color _ink = Color(0xFF2C2925);

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

  static const List<IconData> _icons = [
    Icons.home_outlined,
    Icons.checkroom_outlined,
    Icons.grid_view_outlined,
    Icons.receipt_long_outlined,
  ];

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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          // Outer row centres the content-sized pill horizontally without an
          // unbounded-height Center wrapper.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                // Floating pill hugging the icon cluster — hairline border,
                // no shadow. Width follows the icons plus this padding.
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  // Fully rounded pill ends (radius = half the bar height).
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_icons.length, (index) {
                    return _buildNavItem(index);
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final bool isActive = currentPageIndex == index;
    final Color color = isActive ? _ink : AppColors.deepAccent;

    return SizedBox(
      // Fixed tap-target width sets the spacing between the four icons; wider
      // than the icon so they read as evenly spaced, not edge-to-edge.
      width: 84,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => currentPageIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icons[index], size: 28, color: color),
            const SizedBox(height: 2),
            // 5px Taupe dot under the active item; reserved space otherwise so
            // the icons never shift vertically.
            SizedBox(
              height: 5,
              width: 5,
              child: isActive
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.deepAccent,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
