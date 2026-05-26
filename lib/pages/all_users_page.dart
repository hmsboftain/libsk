import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class AllUsersPage extends StatelessWidget {
  const AllUsersPage({super.key});

  String _buildUserName(Map<String, dynamic> data) {
    final fullName = data['fullName']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) return fullName;

    final firstName = data['firstName']?.toString().trim() ?? '';
    final lastName = data['lastName']?.toString().trim() ?? '';
    final combined = '$firstName $lastName'.trim();

    if (combined.isNotEmpty) return combined;

    return 'User';
  }

  String _buildUserEmail(Map<String, dynamic> data) {
    return data['email']?.toString().trim().isNotEmpty == true
        ? data['email'].toString().trim()
        : 'No email';
  }

  String _buildUserPhone(Map<String, dynamic> data) {
    return data['phone']?.toString().trim().isNotEmpty == true
        ? data['phone'].toString().trim()
        : 'No phone number';
  }

  Widget buildUserCard({
    required String name,
    required String email,
    required String phone,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.softAccent.withValues(alpha: 0.22),
            child: const Icon(
              Icons.person_outline,
              color: AppColors.deepAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getAllUsersStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Failed to load users',
                        style: AppTextStyles.bodyMedium,
                      ),
                    );
                  }

                  final userDocs = snapshot.data?.docs ?? [];

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ALL USERS',
                          style: AppTextStyles.displayMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${userDocs.length} registered users',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (userDocs.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.zero,
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.5,
                              ),
                            ),
                            child: const Text(
                              'No users found.',
                              style: AppTextStyles.bodyMedium,
                            ),
                          )
                        else
                          ...userDocs.map((doc) {
                            final data = doc.data();

                            final name = _buildUserName(data);
                            final email = _buildUserEmail(data);
                            final phone = _buildUserPhone(data);

                            return buildUserCard(
                              name: name,
                              email: email,
                              phone: phone,
                            );
                          }),
                      ],
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