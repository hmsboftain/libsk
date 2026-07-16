import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/validators.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Widget _contactTile({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.deepAccent, size: 22),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.labelLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: AppColors.secondaryText,
          ),
        ],
      ),
    ),
  );
}

Widget _formField({
  required TextEditingController controller,
  required String hint,
  required IconData icon,
  TextInputType keyboardType = TextInputType.text,
  int maxLines = 1,
  TextInputAction? textInputAction,
  VoidCallback? onEditingComplete,
}) {
  return TextField(
    controller: controller,
    keyboardType: keyboardType,
    maxLines: maxLines,
    textInputAction: textInputAction,
    onEditingComplete: onEditingComplete,
    style: AppTextStyles.bodyMedium,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.secondaryText,
      ),
      prefixIcon: maxLines == 1
          ? Icon(icon, color: AppColors.deepAccent, size: 20)
          : null,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: maxLines > 1 ? 14 : 0,
      ),
    ),
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();

  bool _isSending = false;
  String? _successMessage;
  String? _errorMessage;

  int? _expandedTopic;
  int? _expandedFaq;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _emailController.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final message = _messageController.text.trim();

    final preflight =
        Validators.maxLength(name, 100, 'Name') ??
        Validators.email(email) ??
        Validators.maxLength(message, 1000, 'Message');
    if (preflight != null) {
      setState(() {
        _errorMessage = preflight;
        _successMessage = null;
      });
      return;
    }

    // Manual required checks (Validators.required not needed — maxLength covers empty)
    if (name.isEmpty || email.isEmpty || message.isEmpty) {
      setState(() {
        _errorMessage = l10n.fillAllFields;
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('support_messages').add({
        'name': name,
        'email': email,
        'message': message,
        'uid': user?.uid ?? '',
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _successMessage = l10n.messageSentSuccessfully;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = l10n.somethingWentWrong;
      });
    }
  }

  List<Map<String, dynamic>> _buildTopics(AppLocalizations l10n) {
    return [
      {
        'icon': Icons.receipt_long_outlined,
        'label': l10n.helpTopicOrders,
        'faqs': [
          {'q': l10n.helpOrdersQ1, 'a': l10n.helpOrdersA1},
          {'q': l10n.helpOrdersQ2, 'a': l10n.helpOrdersA2},
          {'q': l10n.helpOrdersQ3, 'a': l10n.helpOrdersA3},
          {'q': l10n.helpOrdersQ4, 'a': l10n.helpOrdersA4},
        ],
      },
      {
        'icon': Icons.local_shipping_outlined,
        'label': l10n.helpTopicDelivery,
        'faqs': [
          {'q': l10n.helpDeliveryQ1, 'a': l10n.helpDeliveryA1},
          {'q': l10n.helpDeliveryQ2, 'a': l10n.helpDeliveryA2},
          {'q': l10n.helpDeliveryQ3, 'a': l10n.helpDeliveryA3},
        ],
      },
      {
        'icon': Icons.autorenew_outlined,
        'label': l10n.helpTopicReturns,
        'faqs': [
          {'q': l10n.helpReturnsQ1, 'a': l10n.helpReturnsA1},
          {'q': l10n.helpReturnsQ2, 'a': l10n.helpReturnsA2},
          {'q': l10n.helpReturnsQ3, 'a': l10n.helpReturnsA3},
        ],
      },
      {
        'icon': Icons.payment_outlined,
        'label': l10n.helpTopicPayment,
        'faqs': [
          {'q': l10n.helpPaymentQ1, 'a': l10n.helpPaymentA1},
          {'q': l10n.helpPaymentQ2, 'a': l10n.helpPaymentA2},
          {'q': l10n.helpPaymentQ3, 'a': l10n.helpPaymentA3},
        ],
      },
      {
        'icon': Icons.person_outline,
        'label': l10n.helpTopicAccount,
        'faqs': [
          {'q': l10n.helpAccountQ1, 'a': l10n.helpAccountA1},
          {'q': l10n.helpAccountQ2, 'a': l10n.helpAccountA2},
          {'q': l10n.helpAccountQ3, 'a': l10n.helpAccountA3},
        ],
      },
      {
        'icon': Icons.storefront_outlined,
        'label': l10n.helpTopicBoutiques,
        'faqs': [
          {'q': l10n.helpBoutiquesQ1, 'a': l10n.helpBoutiquesA1},
          {'q': l10n.helpBoutiquesQ2, 'a': l10n.helpBoutiquesA2},
          {'q': l10n.helpBoutiquesQ3, 'a': l10n.helpBoutiquesA3},
        ],
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final topics = _buildTopics(l10n);

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
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),

                    // ── About LIBSK ───────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.libskTagline,
                            style: AppTextStyles.headingMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.libskDescription,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.secondaryText,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text(l10n.helpSupport, style: AppTextStyles.headingLarge),
                    const SizedBox(height: 4),
                    Text(
                      l10n.howCanWeHelpYouToday,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Topic grid ────────────────────────────────
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: topics.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.0,
                          ),
                      itemBuilder: (context, index) {
                        final topic = topics[index];
                        final isSelected = _expandedTopic == index;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _expandedTopic = isSelected ? null : index;
                            _expandedFaq = null;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.selectedSoft
                                  : AppColors.card,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.deepAccent
                                    : AppColors.border,
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  topic['icon'] as IconData,
                                  color: AppColors.deepAccent,
                                  size: 26,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  topic['label'] as String,
                                  style: AppTextStyles.labelSmall.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? AppColors.deepAccent
                                        : AppColors.primaryText,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // ── FAQs ──────────────────────────────────────
                    if (_expandedTopic != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        topics[_expandedTopic!]['label'] as String,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...(topics[_expandedTopic!]['faqs']
                              as List<Map<String, String>>)
                          .asMap()
                          .entries
                          .map((entry) {
                            final i = entry.key;
                            final faq = entry.value;
                            final isOpen = _expandedFaq == i;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 0.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ListTile(
                                    title: Text(
                                      faq['q']!,
                                      style: AppTextStyles.labelLarge,
                                    ),
                                    trailing: Icon(
                                      isOpen
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: AppColors.deepAccent,
                                    ),
                                    onTap: () => setState(() {
                                      _expandedFaq = isOpen ? null : i;
                                    }),
                                  ),
                                  if (isOpen)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        14,
                                      ),
                                      child: Text(
                                        faq['a']!,
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                              color: AppColors.secondaryText,
                                              height: 1.6,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                    ],

                    const SizedBox(height: 30),

                    // ── Contact ───────────────────────────────────
                    Text(l10n.contactUs, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 12),
                    _contactTile(
                      icon: Icons.email_outlined,
                      title: l10n.emailSupport,
                      subtitle: 'support@libsk.com',
                      onTap: () => _launchUrl('mailto:support@libsk.com'),
                    ),
                    const SizedBox(height: 10),
                    _contactTile(
                      icon: Icons.chat_outlined,
                      title: 'WhatsApp',
                      subtitle: '+965 60700596',
                      onTap: () => _launchUrl('https://wa.me/96560700596'),
                    ),
                    const SizedBox(height: 10),
                    _contactTile(
                      icon: Icons.camera_alt_outlined,
                      title: 'Instagram',
                      subtitle: '@libskapp',
                      onTap: () => _launchUrl('https://instagram.com/libsk'),
                    ),
                    const SizedBox(height: 10),
                    _contactTile(
                      icon: Icons.play_circle_outline,
                      title: 'TikTok',
                      subtitle: '@libskapp',
                      onTap: () => _launchUrl('https://tiktok.com/@libsk'),
                    ),

                    const SizedBox(height: 30),

                    // ── Contact form ──────────────────────────────
                    Text(l10n.sendAMessage, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Column(
                        children: [
                          _formField(
                            controller: _nameController,
                            hint: l10n.yourName,
                            icon: Icons.person_outline,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _formField(
                            controller: _emailController,
                            hint: l10n.yourEmail,
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _formField(
                            controller: _messageController,
                            hint: l10n.describeYourIssue,
                            icon: Icons.message_outlined,
                            maxLines: 4,
                            textInputAction: TextInputAction.done,
                            onEditingComplete: () =>
                                FocusScope.of(context).unfocus(),
                          ),
                          const SizedBox(height: 16),
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _errorMessage!,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.deepAccent,
                                ),
                              ),
                            ),
                          if (_successMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _successMessage!,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.primaryText,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSending ? null : _sendMessage,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.deepAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              child: _isSending
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 1.5,
                                      ),
                                    )
                                  : Text(
                                      l10n.sendMessage,
                                      style: AppTextStyles.button,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
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
