import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/boutiques_card.dart';
import 'boutique_oversight_page.dart';
import '../widgets/theme.dart';

class AdminBoutiquesPage extends StatelessWidget {
  const AdminBoutiquesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            const SizedBox(height: 12),
            const Text(
              "All Boutiques",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getAllBoutiquesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text("Failed to load boutiques"),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text("No boutiques available"),
                    );
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();

                      final boutiqueId = doc.id;
                      final imageUrl = data['logoPath']?.toString() ?? '';
                      final boutiqueName =
                          data['name']?.toString() ?? 'Boutique';

                      return BoutiquesCard(
                        imageUrl: imageUrl,
                        boutiqueName: boutiqueName,
                        isLiked: false,
                        onLikeTap: () {},
                        showLikeButton: false,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BoutiqueOversightPage(
                                boutiqueId: boutiqueId,
                              ),
                            ),
                          );
                        },
                      );
                    },
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