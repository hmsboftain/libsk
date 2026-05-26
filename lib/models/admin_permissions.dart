/// Immutable snapshot of an admin user's permission flags, derived from the
/// `admin_users/{uid}` document.
///
/// Callers can fetch a single instance via
/// `FirestoreService.getCurrentUserPermissions()` and read every flag from it
/// instead of issuing one Firestore read per permission check.
class AdminPermissions {
  final bool isApproved;
  final bool isSuperAdmin;
  final bool canManageUsers;
  final bool canManageBoutiques;
  final bool canManageOrders;
  final bool canManageHomepage;
  final bool canViewAnalytics;

  const AdminPermissions({
    required this.isApproved,
    required this.isSuperAdmin,
    required this.canManageUsers,
    required this.canManageBoutiques,
    required this.canManageOrders,
    required this.canManageHomepage,
    required this.canViewAnalytics,
  });

  /// A `null` or missing admin document collapses to "no permissions".
  factory AdminPermissions.fromMap(Map<String, dynamic>? data) {
    if (data == null) return none;

    final approved = data['isApproved'] == true;
    return AdminPermissions(
      isApproved: approved,
      // Every other capability is gated on isApproved so that pulling a
      // single flag in code is sufficient to make an authorization decision.
      isSuperAdmin: approved && data['role'] == 'super_admin',
      canManageUsers: approved && data['canManageUsers'] == true,
      canManageBoutiques: approved && data['canManageBoutiques'] == true,
      canManageOrders: approved && data['canManageOrders'] == true,
      canManageHomepage: approved && data['canManageHomepage'] == true,
      canViewAnalytics: approved && data['canViewAnalytics'] == true,
    );
  }

  /// All-false permission set, used when the user is signed-out, not an
  /// admin, or the admin document does not exist.
  static const AdminPermissions none = AdminPermissions(
    isApproved: false,
    isSuperAdmin: false,
    canManageUsers: false,
    canManageBoutiques: false,
    canManageOrders: false,
    canManageHomepage: false,
    canViewAnalytics: false,
  );
}
