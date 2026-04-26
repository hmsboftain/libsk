import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/main_navigation_bar.dart';
import 'orders_page.dart';
import '../widgets/theme.dart';

class OrderConfirmationPage extends StatelessWidget {
  final String orderNumber;

  const OrderConfirmationPage({
    super.key,
    required this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName != null && user!.displayName!.isNotEmpty)
        ? user.displayName!
        : AppLocalizations.of(context)!.customer;

    final date =
        "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(context)!.orderConfirmation,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 80),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black87,
                    width: 8,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check,
                    size: 70,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                AppLocalizations.of(context)!.yourPaymentWasSuccessful,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "${AppLocalizations.of(context)!.orderNumberLabel} #$orderNumber",
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "${AppLocalizations.of(context)!.dateLabel} $date",
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 25),
              Text(
                "${AppLocalizations.of(context)!.thankYou}, $name",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 55),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.black38),
                ),
                child: Row(
                  children: [
                    Expanded(
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
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(28),
                              bottomLeft: Radius.circular(28),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              AppLocalizations.of(context)!.backToHome,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const OrdersPage(),
                            ),
                                (route) => false,
                          );
                        },
                        child: Center(
                          child: Text(
                            AppLocalizations.of(context)!.orders,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
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