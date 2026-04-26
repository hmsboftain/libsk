import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class FilteredUsersPage extends StatelessWidget {
  final String title;
  final List<String> roles;

  const FilteredUsersPage({
    super.key,
    required this.title,
    required this.roles,
  });

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

  String _buildUserRole(Map<String, dynamic> data) {
    final role = data['role']?.toString().trim() ?? 'user';

    switch (role) {
      case 'boutique_owner':
        return 'Boutique Owner';
      case 'admin':
        return 'Admin';
      case 'super_admin':
        return 'Super Admin';
      default:
        return 'Regular User';
    }
  }

  Widget buildUserCard({
    required String name,
    required String email,
    required String phone,
    required String roleLabel,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.softAccent..withValues(alpha: 0.22),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  roleLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.deepAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesRole(String role) {
    return roles.contains(role);
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
                        style: TextStyle(color: AppColors.secondaryText),
                      ),
                    );
                  }

                  final allDocs = snapshot.data?.docs ?? [];
                  final filteredDocs = allDocs.where((doc) {
                    final role = doc.data()['role']?.toString() ?? 'user';
                    return _matchesRole(role);
                  }).toList();

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${filteredDocs.length} accounts found',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (filteredDocs.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Text(
                              'No users found.',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          )
                        else
                          ...filteredDocs.map((doc) {
                            final data = doc.data();

                            final name = _buildUserName(data);
                            final email = _buildUserEmail(data);
                            final phone = _buildUserPhone(data);
                            final roleLabel = _buildUserRole(data);

                            return buildUserCard(
                              name: name,
                              email: email,
                              phone: phone,
                              roleLabel: roleLabel,
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