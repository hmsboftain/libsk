import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

class BoutiqueOnboardingPage extends StatefulWidget {
  const BoutiqueOnboardingPage({super.key});

  @override
  State<BoutiqueOnboardingPage> createState() => _BoutiqueOnboardingPageState();
}

class _BoutiqueOnboardingPageState extends State<BoutiqueOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;

  // Step tracking
  int _step = 1; // 1 = find user, 2 = boutique details

  // Found user
  String? _foundUid;
  String? _foundName;
  String? _foundEmail;

  final emailController = TextEditingController();
  final boutiqueNameController = TextEditingController();
  final boutiqueDescController = TextEditingController();


  @override
  void dispose() {
    emailController.dispose();
    boutiqueNameController.dispose();
    boutiqueDescController.dispose();
    super.dispose();
  }

  // Step 1 — look up user by email
  Future<void> _findUser() async {
    final l10n = AppLocalizations.of(context)!;
    final email = emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterValidEmail)),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // Check not already a boutique owner
      final ownerCheck = await FirebaseFirestore.instance
          .collection('boutique_owners')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (ownerCheck.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.userAlreadyBoutiqueOwner)),
        );
        return;
      }

      // Look up user by email
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.noAccountFoundAskSignup)),
        );
        return;
      }

      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();

      if (!mounted) return;
      setState(() {
        _foundUid = userDoc.id;
        _foundEmail = email;
        _foundName =
            userData['fullName']?.toString() ??
            '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                .trim();
        _step = 2;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.error}: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Step 2 — create boutique + owner docs
  Future<void> _createBoutique() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (_foundUid == null) return;

    setState(() => isLoading = true);

    try {
      // Create boutique doc
      final boutiqueRef = await FirebaseFirestore.instance
          .collection('boutiques')
          .add({
            'name': boutiqueNameController.text.trim(),
            'description': boutiqueDescController.text.trim(),
            'ownerUid': _foundUid,
            'isActive': true,
            'createdAt': FieldValue.serverTimestamp(),
          });

      // Create boutique_owners doc using owner's UID
      await FirebaseFirestore.instance
          .collection('boutique_owners')
          .doc(_foundUid)
          .set({
            'uid': _foundUid,
            'fullName': _foundName ?? '',
            'email': _foundEmail ?? '',
            'boutiqueId': boutiqueRef.id,
            'boutiqueName': boutiqueNameController.text.trim(),
            'role': 'boutique_owner',
            'isApproved': true,
            'createdAt': FieldValue.serverTimestamp(),
          });

      // Update user role
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_foundUid)
          .update({'role': 'boutique_owner'});

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: const RoundedRectangleBorder(),
          title: Text(l10n.done, style: AppTextStyles.headingSmall),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.boutiqueNowLiveOnLibsk(boutiqueNameController.text.trim()),
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.field,
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.ownerLabel, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 4),
                    Text(_foundName ?? '', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 2),
                    Text(
                      _foundEmail ?? '',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.deepAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.ownerCanNowLogin,
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(l10n.done, style: AppTextStyles.button),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.error}: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  InputDecoration _inputDec(String hint) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: AppColors.border, width: 0.5),
    );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.field,
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.secondaryText,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: AppTextStyles.labelLarge),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: child,
  );

  Widget _stepIndicator() {
    return Row(
      children: [
        _stepDot(1, AppLocalizations.of(context)!.findUser),
        Expanded(
          child: Container(
            height: 0.5,
            color: _step >= 2 ? AppColors.deepAccent : AppColors.border,
          ),
        ),
        _stepDot(2, AppLocalizations.of(context)!.boutiqueDetails),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _step == step;
    final isDone = _step > step;
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone || isActive
                ? AppColors.deepAccent
                : AppColors.imagePlaceholder,
            border: Border.all(
              color: isDone || isActive
                  ? AppColors.deepAccent
                  : AppColors.border,
              width: 0.5,
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '$step',
                    style: AppTextStyles.capsLabel.copyWith(
                      color: isActive ? Colors.white : AppColors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 10,
            color: isActive ? AppColors.deepAccent : AppColors.secondaryText,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.boutiqueOnboarding,
                      style: AppTextStyles.displayMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.upgradeUserToBoutiqueOwner,
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 20),

                    // Step indicator
                    _stepIndicator(),
                    const SizedBox(height: 24),

                    // ── STEP 1 — Find user ──────────────────────────
                    if (_step == 1) ...[
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.findAccount,
                              style: AppTextStyles.capsLabel,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.enterOwnerSignupEmail,
                              style: AppTextStyles.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            _label(l10n.emailAddress),
                            TextField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textInputAction: TextInputAction.done,
                              onEditingComplete: () =>
                                  FocusScope.of(context).unfocus(),
                              decoration: _inputDec(''),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : _findUser,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.deepAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(l10n.findAccount, style: AppTextStyles.button),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── STEP 2 — Boutique details ───────────────────
                    if (_step == 2) ...[
                      // Found user card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.selectedSoft,
                          border: Border.all(
                            color: AppColors.deepAccent,
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              color: AppColors.deepAccent,
                              child: Center(
                                child: Text(
                                  (_foundName?.isNotEmpty == true
                                          ? _foundName![0]
                                          : '?')
                                      .toUpperCase(),
                                  style: AppTextStyles.headingSmall.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _foundName ?? '',
                                    style: AppTextStyles.labelLarge,
                                  ),
                                  Text(
                                    _foundEmail ?? '',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.check_circle_outline,
                              color: AppColors.deepAccent,
                              size: 20,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Boutique info
                            _card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.boutiqueDetails,
                                    style: AppTextStyles.capsLabel,
                                  ),
                                  const SizedBox(height: 14),
                                  _label(l10n.boutique),
                                  TextFormField(
                                    controller: boutiqueNameController,
                                    textInputAction: TextInputAction.next,
                                    decoration: _inputDec(''),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? l10n.requiredField
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  _label(l10n.descriptionOptional),
                                  TextFormField(
                                    controller: boutiqueDescController,
                                    maxLines: 3,
                                    textInputAction: TextInputAction.done,
                                    onEditingComplete: () =>
                                        FocusScope.of(context).unfocus(),
                                    decoration: _inputDec(''),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 22),

                            Row(
                              children: [
                                // Back button
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _step = 1;
                                    _foundUid = null;
                                    _foundName = null;
                                    _foundEmail = null;
                                  }),
                                  child: Container(
                                    height: 54,
                                    width: 54,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.border,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.arrow_back,
                                      size: 18,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 54,
                                    child: ElevatedButton(
                                      onPressed: isLoading
                                          ? null
                                          : _createBoutique,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.deepAccent,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.zero,
                                        ),
                                      ),
                                      child: isLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(l10n.createBoutique, style: AppTextStyles.button),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
