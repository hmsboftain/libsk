import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  static const backgroundColor = AppColors.background;
  static const cardColor = AppColors.card;
  static const borderColor = AppColors.border;
  static const primaryText = AppColors.primaryText;
  static const secondaryText = AppColors.secondaryText;
  static const deepAccent = AppColors.deepAccent;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _isSending = false;
  String? _successMessage;
  String? _errorMessage;

  int? _expandedTopic;
  int? _expandedFaq;

  final List<Map<String, dynamic>> _topics = [
    {
      'icon': Icons.receipt_long_outlined,
      'label': 'Orders',
      'faqs': [
        {
          'q': 'How do I track my order?',
          'a':
          'Once your order is placed, you can track it from the Orders section in your profile. You will see real-time status updates as your order is processed and shipped.',
        },
        {
          'q': 'Can I cancel my order?',
          'a':
          'Orders can be cancelled within 1 hour of placement. After that, the boutique may have already begun processing it. Contact us immediately if you need to cancel.',
        },
        {
          'q': 'My order shows delivered but I haven\'t received it.',
          'a':
          'Please check with neighbours or building reception first. If the item is still missing, contact our support team within 48 hours and we will investigate.',
        },
      ],
    },
    {
      'icon': Icons.local_shipping_outlined,
      'label': 'Delivery',
      'faqs': [
        {
          'q': 'What areas do you deliver to?',
          'a':
          'We currently deliver across all governorates in Kuwait including Capital, Hawalli, Farwaniya, Ahmadi, Jahra, and Mubarak Al-Kabeer.',
        },
        {
          'q': 'How long does delivery take?',
          'a':
          'Standard delivery takes 2–4 business days depending on the boutique and your location. Some boutiques offer same-day delivery within Kuwait City.',
        },
        {
          'q': 'Is there a delivery fee?',
          'a':
          'Delivery fees vary by boutique and are shown at checkout before you confirm your order.',
        },
      ],
    },
    {
      'icon': Icons.autorenew_outlined,
      'label': 'Returns',
      'faqs': [
        {
          'q': 'What is the return policy?',
          'a':
          'Return policies are set by each boutique individually. You can find the return policy on the boutique\'s storefront page before purchasing.',
        },
        {
          'q': 'How do I return an item?',
          'a':
          'To initiate a return, go to your Orders, select the item, and tap Request Return. Our team will coordinate with the boutique on your behalf.',
        },
        {
          'q': 'How long do refunds take?',
          'a':
          'Once a return is approved, refunds are processed within 5–7 business days depending on your payment method.',
        },
      ],
    },
    {
      'icon': Icons.payment_outlined,
      'label': 'Payment',
      'faqs': [
        {
          'q': 'What payment methods are accepted?',
          'a':
          'We currently accept cash on delivery and card payments via KNET and Visa/Mastercard depending on the boutique.',
        },
        {
          'q': 'Is my payment information secure?',
          'a':
          'Yes. We do not store any card details. All transactions are processed through secure, encrypted payment gateways.',
        },
        {
          'q': 'I was charged but my order wasn\'t placed.',
          'a':
          'This can happen due to a connection issue. Please contact us immediately with your payment reference and Order Number and we will resolve it within 24 hours.',
        },
      ],
    },
    {
      'icon': Icons.person_outline,
      'label': 'Account',
      'faqs': [
        {
          'q': 'How do I change my password?',
          'a':
          'Go to Profile, tap Your Account, then tap Change Password. You will receive a reset link to your registered email.',
        },
        {
          'q': 'How do I update my delivery address?',
          'a':
          'Go to Profile, then Saved Addresses. You can add, edit, or remove addresses at any time.',
        },
        {
          'q': 'How do I delete my account?',
          'a':
          'To delete your account, contact our support team. Account deletion is permanent and cannot be undone.',
        },
      ],
    },
    {
      'icon': Icons.storefront_outlined,
      'label': 'Boutiques',
      'faqs': [
        {
          'q': 'How do I become a boutique owner on LIBSK?',
          'a':
          'Tap Apply as Boutique Owner on the homepage or contact us directly. Our team will review your application and get back to you within 3 business days.',
        },
        {
          'q': 'Can I save a boutique to view later?',
          'a':
          'Yes. Tap the save icon on any boutique storefront to add it to your Saved Boutiques in your profile.',
        },
        {
          'q': 'A boutique is not responding to my order.',
          'a':
          'If a boutique has not updated your order status within 48 hours, contact our support team and we will follow up on your behalf.',
        },
      ],
    },
  ];

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
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final message = _messageController.text.trim();

    if (name.isEmpty || email.isEmpty || message.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields.';
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

      setState(() {
        _isSending = false;
        _successMessage =
        'Your message has been sent. We will get back to you shortly.';
      });
    } catch (e) {
      setState(() {
        _isSending = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'Help & Support',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'How can we help you today?',
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryText,
                      ),
                    ),
                    const SizedBox(height: 24),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _topics.length,
                      gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.0,
                      ),
                      itemBuilder: (context, index) {
                        final topic = _topics[index];
                        final isSelected = _expandedTopic == index;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _expandedTopic = isSelected ? null : index;
                              _expandedFaq = null;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.selectedSoft
                                  : cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? deepAccent
                                    : borderColor,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  topic['icon'] as IconData,
                                  color: deepAccent,
                                  size: 26,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  topic['label'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? AppColors.deepAccent
                                        : primaryText,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    if (_expandedTopic != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        _topics[_expandedTopic!]['label'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: primaryText,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...(_topics[_expandedTopic!]['faqs']
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
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                title: Text(
                                  faq['q']!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: primaryText,
                                  ),
                                ),
                                trailing: Icon(
                                  isOpen
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: deepAccent,
                                ),
                                onTap: () {
                                  setState(() {
                                    _expandedFaq = isOpen ? null : i;
                                  });
                                },
                              ),
                              if (isOpen)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 14),
                                  child: Text(
                                    faq['a']!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: secondaryText,
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
                    const Text(
                      'CONTACT US',
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _contactTile(
                      icon: Icons.email_outlined,
                      title: 'Email Support',
                      subtitle: 'support@libsk.app',
                      onTap: () => _launchUrl('mailto:support@libsk.app'),
                    ),
                    const SizedBox(height: 10),

                    _contactTile(
                      icon: Icons.chat_outlined,
                      title: 'WhatsApp',
                      subtitle: '+965 123 456 789',
                      onTap: () =>
                          _launchUrl('https://wa.me/965123456789'),
                    ),

                    const SizedBox(height: 30),
                    const Text(
                      'SEND A MESSAGE',
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        children: [
                          _formField(
                            controller: _nameController,
                            hint: 'Your name',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 12),
                          _formField(
                            controller: _emailController,
                            hint: 'Your email',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),
                          _formField(
                            controller: _messageController,
                            hint: 'Describe your issue or question',
                            icon: Icons.message_outlined,
                            maxLines: 4,
                          ),
                          const SizedBox(height: 16),
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          if (_successMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _successMessage!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSending ? null : _sendMessage,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isSending
                                  ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                                  : const Text(
                                'Send Message',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
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
    );
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
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: deepAccent, size: 22),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: secondaryText,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.black38),
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
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
        prefixIcon: maxLines == 1
            ? Icon(icon, color: deepAccent, size: 20)
            : null,
        filled: true,
        fillColor: AppColors.field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: maxLines > 1 ? 14 : 0,
        ),
      ),
    );
  }
}