import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/boutiques_card.dart';
import '../services/firestore_service.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';

class SavedBoutiquesPage extends StatefulWidget {
  const SavedBoutiquesPage({super.key});

  @override
  State<SavedBoutiquesPage> createState() => _SavedBoutiquesPageState();
}

class _SavedBoutiquesPageState extends State<SavedBoutiquesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.savedBoutiques,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getSavedBoutiquesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        AppLocalizations.of(context)!
                            .failedToLoadSavedBoutiques,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () async {
                        setState(() {});
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: 400,
                          child: Center(
                            child: Text(
                              AppLocalizations.of(context)!
                                  .noSavedBoutiquesYet,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() {});
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: docs.map((doc) {
                        final boutique = doc.data();

                        final String boutiqueId = boutique["boutiqueId"] ?? "";
                        final String imageUrl = boutique["imageUrl"] ?? "";
                        final String boutiqueName =
                            boutique["boutiqueName"] ?? "";

                        return BoutiquesCard(
                          imageUrl: imageUrl,
                          boutiqueName: boutiqueName,
                          isLiked: true,
                          onLikeTap: () async {
                            final loc = AppLocalizations.of(context)!;
                            final messenger = ScaffoldMessenger.of(context);
                            await FirestoreService.removeSavedBoutique(boutiqueId);
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(loc.boutiqueRemovedFromSaved),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BoutiqueStorefrontPage(
                                  boutiqueId: boutiqueId,
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
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