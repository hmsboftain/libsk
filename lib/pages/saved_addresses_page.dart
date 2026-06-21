import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'add_address_page.dart';

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

  Future<void> _deleteAddress(String docId) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirestoreService.deleteAddress(docId);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.addressRemoved),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failedToRemoveAddress)),
      );
    }
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
            Text(l10n.savedAddresses, style: AppTextStyles.displayMedium),
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
                    return ErrorStateWidget.inline(
                      title: l10n.failedToLoadAddresses,
                      message: l10n.pullDownToRetry,
                      onRetry: () => setState(() {}),
                      type: ErrorType.network,
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () async => setState(() {}),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: 400,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                              ),
                              child: Text(
                                l10n.noSavedAddressesYet,
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
                    onRefresh: () async => setState(() {}),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) => _AddressCard(
                        doc: docs[index],
                        l10n: l10n,
                        onDelete: _deleteAddress,
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 70,
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddAddressPage()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(
                  l10n.addNewAddress,
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

// ── Address card widget ───────────────────────────────────────────────────────

class _AddressCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AppLocalizations l10n;
  final Future<void> Function(String docId) onDelete;

  const _AddressCard({
    required this.doc,
    required this.l10n,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final address = doc.data();
    final floor = address['floor']?.toString() ?? '';
    final apartment = address['apartment']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${address['firstName']} ${address['lastName']}',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onDelete(doc.id),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${address['governorate']}, ${address['area']}',
            style: AppTextStyles.bodyMedium,
          ),
          Text(
            l10n.blockStreetLine(
              address['block']?.toString() ?? '',
              address['street']?.toString() ?? '',
            ),
            style: AppTextStyles.bodyMedium,
          ),
          Text(
            l10n.houseBuildingValue(address['house']?.toString() ?? ''),
            style: AppTextStyles.bodyMedium,
          ),
          if (floor.isNotEmpty)
            Text(l10n.floorValue(floor), style: AppTextStyles.bodyMedium),
          if (apartment.isNotEmpty)
            Text(
              l10n.apartmentValue(apartment),
              style: AppTextStyles.bodyMedium,
            ),
          const SizedBox(height: 8),
          Text(
            l10n.phoneValue(address['phone']?.toString() ?? ''),
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}
