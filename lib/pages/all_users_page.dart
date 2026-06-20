import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class AllUsersPage extends StatefulWidget {
  const AllUsersPage({super.key});

  @override
  State<AllUsersPage> createState() => _AllUsersPageState();
}

class _AllUsersPageState extends State<AllUsersPage> {
  final ScrollController _scrollController = ScrollController();
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _error = false;
  int? _totalCount;
  DocumentSnapshot<Map<String, dynamic>>? _cursor;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadMore();
  }

  Future<void> _loadInitial() async {
    try {
      final countFuture = FirestoreService.getUsersCount();
      final snap = await FirestoreService.fetchUsersPage();
      final count = await countFuture;
      if (!mounted) return;
      setState(() {
        _docs.addAll(snap.docs);
        _cursor = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMore = snap.docs.length == FirestoreService.adminPageSize;
        _totalCount = count;
        _loading = false;
      });
    } catch (e) {
      debugPrint('USERS LOAD ERROR: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final snap = await FirestoreService.fetchUsersPage(startAfter: _cursor);
      if (!mounted) return;
      setState(() {
        _docs.addAll(snap.docs);
        _cursor = snap.docs.isNotEmpty ? snap.docs.last : _cursor;
        _hasMore = snap.docs.length == FirestoreService.adminPageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('USERS LOAD MORE ERROR: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  String _buildUserName(Map<String, dynamic> data) {
    final fullName = data['fullName']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) return fullName;

    final firstName = data['firstName']?.toString().trim() ?? '';
    final lastName = data['lastName']?.toString().trim() ?? '';
    final combined = '$firstName $lastName'.trim();

    if (combined.isNotEmpty) return combined;

    return 'User';
  }

  String _buildUserEmail(Map<String, dynamic> data) {
    return data['email']?.toString().trim().isNotEmpty == true
        ? data['email'].toString().trim()
        : 'No email';
  }

  String _buildUserPhone(Map<String, dynamic> data) {
    return data['phone']?.toString().trim().isNotEmpty == true
        ? data['phone'].toString().trim()
        : 'No phone number';
  }

  Widget buildUserCard({
    required String name,
    required String email,
    required String phone,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.softAccent.withValues(alpha: 0.22),
            child: const Icon(
              Icons.person_outline,
              color: AppColors.deepAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ALL USERS',
          style: AppTextStyles.displayMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '${_totalCount ?? _docs.length} registered users',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.deepAccent),
      );
    }

    if (_error) {
      return const Center(
        child: Text('Failed to load users', style: AppTextStyles.bodyMedium),
      );
    }

    if (_docs.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: const Text(
                'No users found.',
                style: AppTextStyles.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      itemCount: _docs.length + 2, // header + footer loader
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader();
        if (index == _docs.length + 1) {
          if (!_loadingMore) return const SizedBox.shrink();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.deepAccent,
                strokeWidth: 1.5,
              ),
            ),
          );
        }
        final data = _docs[index - 1].data();
        return buildUserCard(
          name: _buildUserName(data),
          email: _buildUserEmail(data),
          phone: _buildUserPhone(data),
        );
      },
    );
  }
}
