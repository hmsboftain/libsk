import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../services/firestore_service.dart';
import '../widgets/theme.dart';

/// Super-admin tooling for founding-partner promo credit.
///
/// Two jobs, both server-side (every credit write is a Cloud Function — see
/// firestore.rules; nothing here writes the ledger directly):
///   • The ONE-TIME launch recharge — grants Week-1 credit to every boutique
///     flagged `promoCreditPending` at signup and schedules its Week-2 grant.
///     Idempotent server-side, so a re-run only picks up stragglers.
///   • Manual `admin_adjustment` — goodwill top-ups, a boutique joining
///     mid-cohort (never marked pending), or a dispute clawback.
///
/// A single boutiques stream drives both the pending count and the adjust list,
/// so the list is itself the live confirmation that a recharge landed.
class PromoCreditAdminPage extends StatefulWidget {
  const PromoCreditAdminPage({super.key});

  @override
  State<PromoCreditAdminPage> createState() => _PromoCreditAdminPageState();
}

class _PromoCreditAdminPageState extends State<PromoCreditAdminPage> {
  final _search = TextEditingController();
  bool _running = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  double _balanceOf(Map<String, dynamic> d) =>
      (d['promoCreditBalance'] as num?)?.toDouble() ?? 0;

  Future<void> _runRecharge(int pendingCount) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(),
        title: Text(
          l10n.promoCreditLaunchRecharge,
          style: AppTextStyles.headingSmall,
        ),
        content: Text(
          l10n.promoCreditRechargeConfirm('$pendingCount'),
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _running = true);
    try {
      final r = await FirestoreService.rechargeFoundingPartnerCredits();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.promoCreditRechargeResult('${r.recharged}', '${r.skipped}'),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? l10n.somethingWentWrong)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _openAdjust(String id, Map<String, dynamic> data) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<({double applied, double newBalance})>(
      context: context,
      builder: (_) => _AdjustCreditDialog(
        boutiqueId: id,
        boutiqueName: data['name']?.toString() ?? '',
        currentBalance: _balanceOf(data),
      ),
    );
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.promoCreditAdjustResult(
            result.applied.toStringAsFixed(3),
            result.newBalance.toStringAsFixed(3),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.primaryText,
        title: Text(l10n.promoCreditAdmin, style: AppTextStyles.labelLarge),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.getAllBoutiquesStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            final pending =
                docs.where((d) => d.data()['promoCreditPending'] == true).length;

            // Founding partners first, then alphabetical — the cohort this page
            // exists for stays at the top.
            final query = _search.text.trim().toLowerCase();
            final listed = docs.where((d) {
              if (query.isEmpty) return true;
              return (d.data()['name']?.toString() ?? '')
                  .toLowerCase()
                  .contains(query);
            }).toList()
              ..sort((a, b) {
                final af = a.data()['foundingPartner'] == true ? 0 : 1;
                final bf = b.data()['foundingPartner'] == true ? 0 : 1;
                if (af != bf) return af.compareTo(bf);
                return (a.data()['name']?.toString() ?? '')
                    .compareTo(b.data()['name']?.toString() ?? '');
              });

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                _rechargeCard(l10n, pending),
                const SizedBox(height: 22),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.promoCreditSearchBoutiques,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                for (final d in listed)
                  _boutiqueRow(l10n, d.id, d.data()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _rechargeCard(AppLocalizations l10n, int pending) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch_outlined,
                  size: 20, color: AppColors.deepAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.promoCreditLaunchRecharge,
                  style: AppTextStyles.bodyLarge
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (pending > 0) _badge(l10n.promoCreditPendingCount('$pending')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.promoCreditLaunchRechargeDesc,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 14),
          if (pending == 0)
            Text(
              l10n.promoCreditNoPending,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.secondaryText),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _running ? null : () => _runRecharge(pending),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.softAccent,
                  disabledForegroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: _running
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 1.5,
                        ),
                      )
                    : Text(l10n.promoCreditRunRecharge,
                        style: AppTextStyles.button),
              ),
            ),
        ],
      ),
    );
  }

  Widget _boutiqueRow(
      AppLocalizations l10n, String id, Map<String, dynamic> data) {
    final balance = _balanceOf(data);
    final founding = data['foundingPartner'] == true;
    final pending = data['promoCreditPending'] == true;
    return InkWell(
      onTap: () => _openAdjust(id, data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (founding) ...[
                        _badge(l10n.promoCreditFoundingBadge),
                        const SizedBox(width: 6),
                      ],
                      if (pending) _badge(l10n.promoCreditPendingBadge),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.promoPriceKwd(balance.toStringAsFixed(3)),
              style: AppTextStyles.labelLarge.copyWith(
                color: balance > 0
                    ? AppColors.deepAccent
                    : AppColors.secondaryText,
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.secondaryText),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.field,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Text(
          text,
          style: AppTextStyles.labelSmall
              .copyWith(fontSize: 10, color: AppColors.secondaryText),
        ),
      );
}

/// Issues a manual `admin_adjustment` against one boutique. Positive grants
/// credit (with an optional expiry), negative claws it back — the server clamps
/// a clawback to the live balance and reports what it actually applied.
class _AdjustCreditDialog extends StatefulWidget {
  final String boutiqueId;
  final String boutiqueName;
  final double currentBalance;

  const _AdjustCreditDialog({
    required this.boutiqueId,
    required this.boutiqueName,
    required this.currentBalance,
  });

  @override
  State<_AdjustCreditDialog> createState() => _AdjustCreditDialogState();
}

class _AdjustCreditDialogState extends State<_AdjustCreditDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _expiry = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _expiry.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount == 0) {
      setState(() => _error = l10n.promoCreditAmountRequired);
      return;
    }
    final expiryText = _expiry.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await FirestoreService.adjustPromoCredit(
        boutiqueId: widget.boutiqueId,
        amount: amount,
        reason: _reason.text.trim(),
        expiresInDays: expiryText.isEmpty ? null : int.tryParse(expiryText),
      );
      if (!mounted) return;
      Navigator.of(context).pop(r);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message ?? l10n.somethingWentWrong;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(),
      title: Text(l10n.promoCreditAdjustTitle, style: AppTextStyles.headingSmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.boutiqueName,
            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.promoPriceKwd(widget.currentBalance.toStringAsFixed(3)),
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(
              hintText: l10n.promoCreditAmountHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            decoration: InputDecoration(
              hintText: l10n.promoCreditReasonHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _expiry,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: l10n.promoCreditExpiryHint,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.deepAccent),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              : Text(l10n.promoCreditApply),
        ),
      ],
    );
  }
}
