/// Role constants to avoid magic strings throughout the app.
/// These match the values stored in Supabase `app_metadata.role`
/// and `users_profile.role`.
/// NOTE: 'owner' is NOT a role — ownership is tracked via organizations.owner_id.
class AppRoles {
  AppRoles._(); // Prevent instantiation

  static const String admin = 'admin';
  static const String rrpp = 'rrpp';
  static const String door = 'door';

  /// Roles with admin-level access
  static const List<String> adminLevel = [admin];

  /// All valid roles for dropdown menus, etc.
  static const List<String> all = [admin, rrpp, door];

  /// Human-readable labels
  static String label(String role) {
    switch (role) {
      case admin:
        return 'Admin';
      case rrpp:
        return 'RRPP';
      case door:
        return 'Door/Puerta';
      default:
        return role.toUpperCase();
    }
  }

  /// Check if a role has admin privileges
  static bool isAdmin(String? role) => role == admin;
}
