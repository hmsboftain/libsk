import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain model for a user document stored under `users/{uid}`.
class AppUser {
  final String uid;
  final String firstName;
  final String lastName;
  final String fullName;
  final String email;
  final String phone;
  final String role;
  final bool isActive;
  final String? fcmToken;

  const AppUser({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.isActive,
    required this.fcmToken,
  });

  factory AppUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final firstName = (data['firstName'] ?? '').toString();
    final lastName = (data['lastName'] ?? '').toString();
    final storedFullName = (data['fullName'] ?? '').toString();
    final derivedFullName = '$firstName $lastName'.trim();

    return AppUser(
      uid: doc.id,
      firstName: firstName,
      lastName: lastName,
      fullName: storedFullName.isNotEmpty ? storedFullName : derivedFullName,
      email: (data['email'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      role: (data['role'] ?? '').toString(),
      // Defaults to true so that existing documents written before this flag
      // existed continue to behave as active accounts.
      isActive: data['isActive'] != false,
      fcmToken: data['fcmToken']?.toString(),
    );
  }
}
