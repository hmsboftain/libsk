import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../widgets/boutiques_card.dart';
import '../services/firestore_service.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';

class BoutiquesPage extends StatefulWidget {
  const BoutiquesPage({super.key});

  @override
  State<BoutiquesPage> createState() => _BoutiquesPageState();
}

class _BoutiquesPageState extends State<BoutiquesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> toggleBoutiqueLike({
    required String boutiqueId,
    required String imageUrl,
    required String boutiqueName,
    required bool isCurrentlyLiked,
  }) async {
    try {
      if (isCurrentlyLiked) {
        await FirestoreService.removeSavedBoutique(boutiqueId);
      } else {
        await FirestoreService.saveBoutique(
          boutiqueId: boutiqueId,
          imageUrl: imageUrl,
          boutiqueName: boutiqueName,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCurrentlyLiked
                ? 'Boutique removed from saved boutiques'
                : 'Boutique saved',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _openBoutiqueStorefront(String boutiqueId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BoutiqueStorefrontPage(
          boutiqueId: boutiqueId,
        ),
      ),
    );
  }

  Set<String> _getSavedBoutiqueIds(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    return docs.map((doc) => doc.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final boutiquesStream =
    _firestore.collection('boutiques').orderBy('name').snapshots();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(),
            const SizedBox(height: 12),
            const Text(
              'Boutiques',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getSavedBoutiquesStream(),
                builder: (context, savedSnapshot) {
                  final savedDocs = savedSnapshot.data?.docs ?? [];
                  final savedBoutiqueIds = _getSavedBoutiqueIds(savedDocs);

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: boutiquesStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Failed to load boutiques'),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No boutiques available'),
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

                          final isLiked =
                          savedBoutiqueIds.contains(boutiqueId);

                          return BoutiquesCard(
                            imageUrl: imageUrl,
                            boutiqueName: boutiqueName,
                            isLiked: isLiked,
                            onLikeTap: () {
                              toggleBoutiqueLike(
                                boutiqueId: boutiqueId,
                                imageUrl: imageUrl,
                                boutiqueName: boutiqueName,
                                isCurrentlyLiked: isLiked,
                              );
                            },
                            onTap: () {
                              _openBoutiqueStorefront(boutiqueId);
                            },
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