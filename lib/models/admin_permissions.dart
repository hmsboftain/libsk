/// Immutable snapshot of the admin identity, derived from the
/// `admin_users/{uid}` document.
///
/// The app runs a single admin tier — the sole `super_admin`. The former
/// granular capability flags (canManageUsers, canManageBoutiques, …) were
/// removed: nothing ever wrote them to an admin_users doc and no rule read
/// them, so authorization is `isSuperAdmin` (isApproved && role) alone.
///
/// Callers fetch a single instance via
/// `FirestoreService.getCurrentUserPermissions()`.
class AdminPermissions {
  final bool isApproved;
  final bool isSuperAdmin;

  const AdminPermissions({
    required this.isApproved,
    required this.isSuperAdmin,
  });

  /// A `null` or missing admin document collapses to "no permissions".
  factory AdminPermissions.fromMap(Map<String, dynamic>? data) {
    if (data == null) return none;

    final approved = data['isApproved'] == true;
    return AdminPermissions(
      isApproved: approved,
      isSuperAdmin: approved && data['role'] == 'super_admin',
    );
  }

  /// All-false permission set, used when the user is signed-out, not an
  /// admin, or the admin document does not exist.
  static const AdminPermissions none = AdminPermissions(
    isApproved: false,
    isSuperAdmin: false,
  );
}
