import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'users';

  // Create a new user (admin or manager)
  Future<void> createUser(User user) async {
    try {
      await _firestore.collection(_collection).doc(user.id).set(user.toMap());
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  // Get user by email
  Future<User?> getUserByEmail(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('email', isEqualTo: email)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      final doc = querySnapshot.docs.first;
      return User.fromMap(doc.data());
    } catch (e) {
      throw Exception('Failed to get user: $e');
    }
  }

  // Get user by ID
  Future<User?> getUserById(String id) async {
    try {
      final doc = await _firestore.collection(_collection).doc(id).get();
      if (!doc.exists) {
        return null;
      }
      return User.fromMap(doc.data()!);
    } catch (e) {
      throw Exception('Failed to get user: $e');
    }
  }

  // Get all managers
  Future<List<User>> getManagers() async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('role', isEqualTo: UserRole.manager.name)
          .where('isActive', isEqualTo: true)
          .get();

      final users = querySnapshot.docs
          .map((doc) => User.fromMap(doc.data()))
          .toList();
      
      // Sort by createdAt descending
      users.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return users;
    } catch (e) {
      throw Exception('Failed to get managers: $e');
    }
  }

  // Get all users (admin only)
  Future<List<User>> getAllUsers() async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('isActive', isEqualTo: true)
          .get();

      final users = querySnapshot.docs
          .map((doc) => User.fromMap(doc.data()))
          .toList();
      
      // Sort by createdAt descending
      users.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return users;
    } catch (e) {
      throw Exception('Failed to get users: $e');
    }
  }

  // Update user
  Future<void> updateUser(User user) async {
    try {
      await _firestore.collection(_collection).doc(user.id).update(user.toMap());
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  // Delete user (soft delete)
  Future<void> deleteUser(String id) async {
    try {
      await _firestore.collection(_collection).doc(id).update({'isActive': false});
    } catch (e) {
      throw Exception('Failed to delete user: $e');
    }
  }

  // Check if email already exists
  Future<bool> emailExists(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Failed to check email: $e');
    }
  }

  // Authenticate user
  Future<User?> authenticate(String email, String password) async {
    try {
      final user = await getUserByEmail(email);
      if (user != null && user.password == password) {
        return user;
      }
      return null;
    } catch (e) {
      throw Exception('Failed to authenticate: $e');
    }
  }
}

