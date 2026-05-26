import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/order_item.dart';
import 'order_details_page.dart';
import 'login_page.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/theme.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  // Nullable so we can skip the Firestore subscription entirely for guests.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _ordersStream;

  @override
  void initState() {
    super.initState();
    if (FirebaseAuth.instance.currentUser != null) {
      _ordersStream = FirestoreService.getOrdersStream();
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return AppColors.deepAccent;
      case 'in transit':
      case 'shipped':
        return AppColors.deepAccent;
      case 'cancelled':
        return AppColors.secondaryText;
      default:
        return AppColors.softAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppHeader(showBackButton: false),
            Expanded(
              child: user == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              size: 36,
                              color: AppColors.softAccent,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Sign in to view your orders',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.headingSmall,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LoginPage(),
                                    ),
                                  );
                                  if (result == true && mounted) {
                                    setState(() {
                                      _ordersStream = FirestoreService
                                          .getOrdersStream();
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.deepAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'Sign In',
                                  style: AppTextStyles.button,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _ordersStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const OrdersListSkeleton();
                        }

                        if (snapshot.hasError) {
                          return ErrorStateWidget.inline(
                            title: 'Something went wrong',
                            message: 'Pull down to retry',
                            onRetry: () => setState(() {}),
                            type: ErrorType.network,
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        final orders = docs.map((doc) {
                          return OrderItem.fromFirestore(doc.id, doc.data());
                        }).toList();

                        return RefreshIndicator(
                          color: AppColors.deepAccent,
                          onRefresh: () async => setState(() {}),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 20),

                                // ── Title ──────────────────────────────
                                Text(
                                  'My Orders',
                                  style: AppTextStyles.displayMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Track your recent purchases',
                                  style: AppTextStyles.bodySmall,
                                ),

                                const SizedBox(height: 20),

                                if (orders.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 80),
                                      child: Column(
                                        children: [
                                          const Icon(
                                            Icons.receipt_long_outlined,
                                            size: 60,
                                            color: AppColors.softAccent,
                                          ),
                                          const SizedBox(height: 18),
                                          Text(
                                            AppLocalizations.of(context)!
                                                .noPastOrdersYet,
                                            style: AppTextStyles.bodyLarge
                                                .copyWith(
                                              color: AppColors.secondaryText,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            AppLocalizations.of(context)!
                                                .completedOrdersWillAppearHere,
                                            textAlign: TextAlign.center,
                                            style: AppTextStyles.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  Column(
                                    children: orders.map((order) {
                                      return GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  OrderDetailsPage(
                                                order: order,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 12),
                                          decoration: BoxDecoration(
                                            color: AppColors.card,
                                            border: Border.all(
                                              color: AppColors.border,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              // Top row — name + price
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        14, 14, 14, 8),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            order.orderNumber,
                                                            style: AppTextStyles
                                                                .headingSmall,
                                                          ),
                                                          const SizedBox(
                                                              height: 3),
                                                          Text(
                                                            '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                                                            style: AppTextStyles
                                                                .bodySmall,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Text(
                                                      'KD ${order.total.toStringAsFixed(0)}',
                                                      style: AppTextStyles
                                                          .labelLarge,
                                                    ),
                                                  ],
                                                ),
                                              ),

                                              const Divider(
                                                color: AppColors.border,
                                                thickness: 0.5,
                                                height: 1,
                                              ),

                                              // Bottom row — status + date
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        14, 10, 14, 12),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 7,
                                                      height: 7,
                                                      decoration: BoxDecoration(
                                                        color: _statusColor(
                                                            order.status),
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 7),
                                                    Text(
                                                      order.status
                                                          .toUpperCase(),
                                                      style: AppTextStyles
                                                          .capsLabel,
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      order.displayDate,
                                                      style: AppTextStyles
                                                          .bodySmall,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),

                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
