import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:libsk/navigation/main_navigation_bar.dart';
import '../pages/cart_page.dart';
import '../pages/search_page.dart';
import '../pages/login_page.dart';
import '../pages/profile_page.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class AppHeader extends StatelessWidget {
  final bool showBackButton;
  final bool isCartPage;

  const AppHeader({
    super.key,
    this.showBackButton = false,
    this.isCartPage = false,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Logo — absolutely centered
            GestureDetector(
              onTap: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        MainNavigationPage(onLanguageChange: (_) {}),
                  ),
                  (route) => false,
                );
              },
              child: Image.asset(
                "assets/libsk_logo.png",
                height: 44,
                fit: BoxFit.contain,
              ),
            ),

            // Left — profile or back
            Align(
              alignment: Alignment.centerLeft,
              child: showBackButton
                  ? GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 26,
                        color: AppColors.primaryText,
                      ),
                    )
                  : GestureDetector(
                      onTap: () async {
                        if (user == null) {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginPage(),
                            ),
                          );
                          if (result == true && context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ProfilePage(),
                              ),
                            );
                          }
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfilePage(),
                            ),
                          );
                        }
                      },
                      child: const Icon(
                        Icons.account_circle_outlined,
                        size: 26,
                        color: AppColors.primaryText,
                      ),
                    ),
            ),

            // Right — cart + search
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: isCartPage
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const CartPage(),
                                  ),
                                );
                              },
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.shopping_bag_outlined,
                            size: 28,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                      if (user != null)
                        Positioned(
                          right: 2,
                          top: 2,
                          child:
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: FirestoreService.getCartItemsStream(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData ||
                                      snapshot.data!.docs.isEmpty) {
                                    return const SizedBox();
                                  }
                                  final count = snapshot.data!.docs.length;
                                  return Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryText,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        count.toString(),
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.background,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                        ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SearchPage(),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.search,
                        size: 28,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
