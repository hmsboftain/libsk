import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../widgets/theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

IconData _iconForType(String routeType) {
  switch (routeType) {
    case 'order_status':
      return Icons.local_shipping_outlined;
    case 'dispute_status':
      return Icons.flag_outlined;
    case 'low_stock':
      return Icons.inventory_2_outlined;
    default:
      return Icons.notifications_none;
  }
}

String _formatWhen(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}/${l.month}/${l.year} · ${two(l.hour)}:${two(l.minute)}';
}

/// The routing map lives at the doc's `data` field (the server's extraData),
/// which carries `type` (e.g. "order_status") + `orderId` — the same shape the
/// push-tap handler consumes.
Map<String, dynamic> _routingData(Map<String, dynamic> notif) {
  final raw = notif['data'];
  return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
}

// ── Page ──────────────────────────────────────────────────────────────────────

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // Older notifications loaded on demand below the live window. They don't
  // change, so a static appended list is correct.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _older = [];
  bool _loadingOlder = false;
  bool _noMoreOlder = false;

  Future<void> _markAllRead() async {
    try {
      await FirestoreService.markAllNotificationsAsRead();
    } catch (_) {
      // Best-effort; the stream reflects whatever actually committed.
    }
  }

  Future<void> _loadOlder(
    QueryDocumentSnapshot<Map<String, dynamic>> liveLast,
  ) async {
    if (_loadingOlder || _noMoreOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final cursor = _older.isNotEmpty ? _older.last : liveLast;
      final snap = await FirestoreService.fetchNotificationsBefore(cursor);
      if (!mounted) return;
      setState(() {
        _older.addAll(snap.docs);
        if (snap.docs.length < 50) _noMoreOlder = true;
      });
    } catch (_) {
      // Leave the button available for a retry.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _onTapNotification(
    String id,
    Map<String, dynamic> notif,
    bool isRead,
  ) {
    // Explicit mark-as-read model: tapping marks that one read (fire-and-forget;
    // the stream updates the row + badge). "Mark all read" is the bulk action.
    if (!isRead) {
      FirestoreService.markNotificationAsRead(id).catchError((_) {});
    }
    // Route through the same handler as a push tap, so behaviour is identical.
    NotificationService.instance.handleNotificationTap(_routingData(notif));
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
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
              child: Row(
                children: [
                  Text(l10n.notifications, style: AppTextStyles.headingLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: _markAllRead,
                    child: Text(
                      l10n.markAllRead,
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.deepAccent),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, thickness: 0.5, height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getRecentNotificationsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  final live = snapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  if (live.isEmpty && _older.isEmpty) {
                    return _EmptyState(l10n: l10n);
                  }

                  // De-dupe defensively so a doc can't render in both windows.
                  final liveIds = live.map((d) => d.id).toSet();
                  final all = <QueryDocumentSnapshot<Map<String, dynamic>>>[
                    ...live,
                    ..._older.where((d) => !liveIds.contains(d.id)),
                  ];
                  final canLoadOlder = live.length >= 50 && !_noMoreOlder;

                  return ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    itemCount: all.length + (canLoadOlder ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= all.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: _loadingOlder
                                ? const CircularProgressIndicator(
                                    color: AppColors.deepAccent)
                                : OutlinedButton(
                                    onPressed: () => _loadOlder(live.last),
                                    child: Text(l10n.loadOlder),
                                  ),
                          ),
                        );
                      }
                      final doc = all[i];
                      return _NotificationRow(
                        notif: doc.data(),
                        onTap: (isRead) =>
                            _onTapNotification(doc.id, doc.data(), isRead),
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

// ── Row ───────────────────────────────────────────────────────────────────────

class _NotificationRow extends StatelessWidget {
  final Map<String, dynamic> notif;
  final void Function(bool isRead) onTap;

  const _NotificationRow({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isRead = notif['isRead'] == true;
    final title = (notif['title'] ?? '').toString();
    final body = (notif['body'] ?? '').toString();
    final routeType = (_routingData(notif)['type'] ?? '').toString();
    final createdAt = notif['createdAt'];
    final when = createdAt is Timestamp ? _formatWhen(createdAt.toDate()) : '';

    return GestureDetector(
      onTap: () => onTap(isRead),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? AppColors.card : AppColors.selectedSoft,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconForType(routeType), size: 22, color: AppColors.deepAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: AppTextStyles.labelLarge.copyWith(
                        fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
                      ),
                    ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.secondaryText,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (when.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(when, style: AppTextStyles.labelSmall),
                  ],
                ],
              ),
            ),
            if (!isRead) ...[
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.deepAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;

  const _EmptyState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_none,
              size: 48, color: AppColors.softAccent),
          const SizedBox(height: 12),
          Text(
            l10n.notificationsEmpty,
            style:
                AppTextStyles.bodyMedium.copyWith(color: AppColors.secondaryText),
          ),
        ],
      ),
    );
  }
}
