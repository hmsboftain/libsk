import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/boutiques_card.dart';
import 'boutique_oversight_page.dart';
import '../widgets/theme.dart';

class AdminBoutiquesPage extends StatefulWidget {
  const AdminBoutiquesPage({super.key});

  @override
  State<AdminBoutiquesPage> createState() => _AdminBoutiquesPageState();
}

class _AdminBoutiquesPageState extends State<AdminBoutiquesPage> {
  // Created once — avoids opening a new Firestore listener on every rebuild
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _boutiquesStream;

  @override
  void initState() {
    super.initState();
    _boutiquesStream = FirestoreService.getAllBoutiquesStream();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            const SizedBox(height: 12),
            Text(l10n.allBoutiques, style: AppTextStyles.headingLarge),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5, color: AppColors.border),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _boutiquesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        l10n.failedToLoadBoutiques,
                        style: AppTextStyles.bodyMedium,
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.noBoutiquesAvailable,
                        style: AppTextStyles.bodyMedium,
                      ),
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
                          data['name']?.toString() ?? l10n.boutique;

                      return BoutiquesCard(
                        imageUrl: imageUrl,
                        boutiqueName: boutiqueName,
                        isLiked: false,
                        onLikeTap: () {},
                        showLikeButton: false,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                BoutiqueOversightPage(boutiqueId: boutiqueId),
                          ),
                        ),
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
