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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          showBackButton
              ? IconButton(
            icon: const Icon(Icons.arrow_back, size: 30),
            onPressed: () {
              Navigator.pop(context);
            },
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
            child: const Icon(Icons.account_circle_outlined, size: 30),
          ),

          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 50),
                child: GestureDetector(
                  onTap: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MainNavigationPage(
                          onLanguageChange: (_) {},
                        ),
                      ),
                          (route) => false,
                    );
                  },
                  child: Image.asset(
                    "assets/libsk_logo.png",
                    height: 60,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_bag_outlined, size: 30),
                onPressed: isCartPage
                    ? null
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CartPage(),
                    ),
                  );
                },
              ),
              if (user != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirestoreService.getCartItemsStream(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const SizedBox();
                      }

                      final count = snapshot.data!.docs.length;

                      return Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryText,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          count.toString(),
                          style: const TextStyle(
                            color: AppColors.card,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),

          const SizedBox(width: 12),

          IconButton(
            icon: const Icon(Icons.search, size: 30),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SearchPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}