import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/main_navigation_bar.dart';
import 'orders_page.dart';
import '../widgets/theme.dart';

class OrderConfirmationPage extends StatelessWidget {
  final String orderNumber;

  const OrderConfirmationPage({super.key, required this.orderNumber});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final user = FirebaseAuth.instance.currentUser;
    final name =
        (user?.displayName != null && user!.displayName!.isNotEmpty)
            ? user.displayName!
            : l10n.customer;

    final now = DateTime.now();
    final date = '${now.day}/${now.month}/${now.year}';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(l10n.orderConfirmation, style: AppTextStyles.headingLarge),
              const SizedBox(height: 10),
              const Divider(color: AppColors.border, thickness: 0.5),
              const SizedBox(height: 80),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.deepAccent, width: 0.5),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check,
                    size: 70,
                    color: AppColors.deepAccent,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                l10n.yourPaymentWasSuccessful,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.orderNumber(orderNumber),
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.orderDate(date),
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 25),
              Text(
                l10n.thankYouWithName(name),
                style: AppTextStyles.headingSmall.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 55),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                MainNavigationPage(onLanguageChange: (_) {}),
                          ),
                          (route) => false,
                        ),
                        child: Ink(
                          color: AppColors.deepAccent,
                          child: Center(
                            child: Text(
                              l10n.backToHome,
                              style: AppTextStyles.button,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OrdersPage(),
                          ),
                          (route) => false,
                        ),
                        child: Center(
                          child: Text(
                            l10n.orders,
                            style: AppTextStyles.labelLarge,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}