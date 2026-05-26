import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import 'add_address_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class SavedAddressesPage extends StatefulWidget {
  const SavedAddressesPage({super.key});

  @override
  State<SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<SavedAddressesPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _addressesStream;

  @override
  void initState() {
    super.initState();
    _addressesStream = FirestoreService.getSavedAddressesStream();
  }

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
              AppLocalizations.of(context)!.savedAddresses,
              style: AppTextStyles.displayMedium,
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _addressesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        AppLocalizations.of(context)!
                            .somethingWentWrongWhileLoadingAddresses,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                        ),
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
                            child: Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 30),
                              child: Text(
                                AppLocalizations.of(context)!
                                    .noSavedAddressesYet,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.secondaryText,
                                ),
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
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final address = doc.data();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border: Border.all(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      "${address["firstName"]} ${address["lastName"]}",
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      final loc = AppLocalizations.of(context)!;
                                      final messenger = ScaffoldMessenger.of(context);

                                      await FirestoreService.deleteAddress(doc.id);

                                      if (!mounted) return;

                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(loc.addressRemoved),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "${address["governorate"]}, ${address["area"]}",
                                style: AppTextStyles.bodyMedium,
                              ),
                              Text(
                                "${AppLocalizations.of(context)!.block} ${address["block"]}, ${AppLocalizations.of(context)!.street} ${address["street"]}",
                                style: AppTextStyles.bodyMedium,
                              ),
                              Text(
                                "${AppLocalizations.of(context)!.houseBuilding}: ${address["house"]}",
                                style: AppTextStyles.bodyMedium,
                              ),
                              if ((address["floor"] ?? "")
                                  .toString()
                                  .isNotEmpty)
                                Text(
                                  "${AppLocalizations.of(context)!.floor}: ${address["floor"]}",
                                  style: AppTextStyles.bodyMedium,
                                ),
                              if ((address["apartment"] ?? "")
                                  .toString()
                                  .isNotEmpty)
                                Text(
                                  "${AppLocalizations.of(context)!.apartment}: ${address["apartment"]}",
                                  style: AppTextStyles.bodyMedium,
                                ),
                              const SizedBox(height: 8),
                              Text(
                                "${AppLocalizations.of(context)!.phone}: ${address["phone"]}",
                                style: AppTextStyles.bodySmall,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 70,
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddAddressPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context)!.addNewAddress,
                  style: AppTextStyles.button.copyWith(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}