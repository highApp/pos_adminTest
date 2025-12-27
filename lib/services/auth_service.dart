import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'user_service.dart';

class AuthService {
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _emailKey = 'user_email';
  static const String _roleKey = 'user_role';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';

  final UserService _userService = UserService();

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  // Login with email and password
  Future<User?> login(String email, String password) async {
    try {
      // First check hardcoded admin (for backward compatibility)
      const String validEmail = 'admin@arsons.com';
      const String validPassword = '11223344';

      if (email == validEmail && password == validPassword) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_isLoggedInKey, true);
        await prefs.setString(_emailKey, email);
        await prefs.setString(_roleKey, UserRole.admin.name);
        await prefs.setString(_userIdKey, 'admin');
        await prefs.setString(_userNameKey, 'Admin');
        
        // Return admin user
        return User(
          id: 'admin',
          name: 'Admin',
          phone: '',
          email: email,
          password: password,
          role: UserRole.admin,
          createdAt: DateTime.now(),
        );
      }

      // Check Firestore for users
      final user = await _userService.authenticate(email, password);
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_isLoggedInKey, true);
        await prefs.setString(_emailKey, email);
        await prefs.setString(_roleKey, user.role.name);
        await prefs.setString(_userIdKey, user.id);
        await prefs.setString(_userNameKey, user.name);
        return user;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Logout
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, false);
    await prefs.remove(_emailKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
  }

  // Get logged in user email
  Future<String?> getLoggedInEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  // Get logged in user role
  Future<UserRole?> getLoggedInRole() async {
    final prefs = await SharedPreferences.getInstance();
    final roleString = prefs.getString(_roleKey);
    if (roleString == null) return null;
    return UserRole.values.firstWhere(
      (e) => e.name == roleString,
      orElse: () => UserRole.manager,
    );
  }

  // Get logged in user
  Future<User?> getLoggedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    if (!isLoggedIn) return null;

    final userId = prefs.getString(_userIdKey);
    final email = prefs.getString(_emailKey);
    final roleString = prefs.getString(_roleKey);
    final name = prefs.getString(_userNameKey);

    if (userId == null || email == null || roleString == null || name == null) {
      return null;
    }

    // If it's the hardcoded admin
    if (userId == 'admin') {
      return User(
        id: 'admin',
        name: name,
        phone: '',
        email: email,
        password: '',
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );
    }

    // Get from Firestore
    return await _userService.getUserById(userId);
  }

  // Check if current user is admin
  Future<bool> isAdmin() async {
    final role = await getLoggedInRole();
    return role == UserRole.admin;
  }
}
