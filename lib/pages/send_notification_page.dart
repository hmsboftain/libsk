import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTextStyles.bodyMedium.copyWith(
      color: AppColors.secondaryText,
    ),
    filled: true,
    fillColor: AppColors.field,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.border, width: 0.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.border, width: 0.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.deepAccent, width: 1),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

// Notification target types — labels are built from l10n, not stored here
const _targetValues = ['all_users', 'boutique_owners', 'admins'];

// ── Page ──────────────────────────────────────────────────────────────────────

class SendNotificationPage extends StatefulWidget {
  const SendNotificationPage({super.key});

  @override
  State<SendNotificationPage> createState() => _SendNotificationPageState();
}

class _SendNotificationPageState extends State<SendNotificationPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _targetType = 'all_users';
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String _targetLabel(String value, AppLocalizations l10n) {
    switch (value) {
      case 'boutique_owners':
        return l10n.boutiqueOwners;
      case 'admins':
        return l10n.admins;
      default:
        return l10n.allUsers;
    }
  }

  Future<void> _sendNotification() async {
    final l10n = AppLocalizations.of(context)!;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.enterTitleAndMessage)));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('sendManualNotification');
      final result = await callable.call({
        'title': title,
        'body': body,
        'targetType': _targetType,
      });
      final broadcast = result.data['broadcast'] == true;
      final sentCount = result.data['sentCount'];

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            broadcast
                ? l10n.notificationSentToAllUsers
                : l10n.notificationSentToUsers((sentCount ?? 0).toString()),
          ),
        ),
      );
      _titleController.clear();
      _bodyController.clear();
      setState(() => _targetType = 'all_users');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToSendNotification(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.sendNotificationTitle,
                      style: AppTextStyles.displayMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.sendNotificationSubtitle,
                      style: AppTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 22),

                    Text(l10n.target, style: AppTextStyles.labelLarge),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _targetType,
                      decoration: _inputDecoration(l10n.selectTarget),
                      items: _targetValues
                          .map(
                            (v) => DropdownMenuItem<String>(
                              value: v,
                              child: Text(_targetLabel(v, l10n)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _targetType = value);
                      },
                    ),

                    const SizedBox(height: 18),
                    Text(
                      l10n.notificationTitleLabel,
                      style: AppTextStyles.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      decoration: _inputDecoration(''),
                    ),

                    const SizedBox(height: 18),
                    Text(l10n.message, style: AppTextStyles.labelLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bodyController,
                      maxLines: 5,
                      decoration: _inputDecoration(''),
                    ),

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _sendNotification,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deepAccent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.softAccent,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                l10n.sendNotificationButton,
                                style: AppTextStyles.button,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
