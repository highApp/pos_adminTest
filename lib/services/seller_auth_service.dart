import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/seller.dart';

class SellerAuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'sellers';

  // Hash password
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  // Register new seller
  Future<Map<String, dynamic>> registerSeller({
    required String name,
    required String phone,
    required String location,
    required String password,
  }) async {
    try {
      // Check if phone already exists
      final existing = await _firestore
          .collection(_collection)
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        return {
          'success': false,
          'message': 'Phone number already registered',
        };
      }

      // Create new seller with hashed password
      final sellerId = _firestore.collection(_collection).doc().id;
      final hashedPassword = _hashPassword(password);

      final seller = {
        'id': sellerId,
        'name': name,
        'phone': phone,
        'location': location,
        'passwordHash': hashedPassword,
        'createdAt': DateTime.now().toIso8601String(),
        'isActive': true,
      };

      await _firestore.collection(_collection).doc(sellerId).set(seller);

      return {
        'success': true,
        'message': 'Registration successful',
        'sellerId': sellerId,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Registration failed: $e',
      };
    }
  }

  // Login seller
  Future<Map<String, dynamic>> loginSeller({
    required String phone,
    required String password,
  }) async {
    try {
      // Find seller by phone
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return {
          'success': false,
          'message': 'Phone number not registered',
        };
      }

      final sellerDoc = querySnapshot.docs.first;
      final sellerData = sellerDoc.data();

      // Check if seller is active
      if (sellerData['isActive'] != true) {
        return {
          'success': false,
          'message': 'Your account has been deactivated. Contact admin.',
        };
      }

      // Verify password
      final hashedPassword = _hashPassword(password);
      if (sellerData['passwordHash'] != hashedPassword) {
        return {
          'success': false,
          'message': 'Incorrect password',
        };
      }

      // Login successful
      return {
        'success': true,
        'message': 'Login successful',
        'seller': Seller.fromMap(sellerData),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Login failed: $e',
      };
    }
  }

  // Get seller by ID
  Future<Seller?> getSellerById(String sellerId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(sellerId).get();
      if (doc.exists) {
        return Seller.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Update seller profile
  Future<bool> updateSellerProfile({
    required String sellerId,
    String? name,
    String? location,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (location != null) updates['location'] = location;

      await _firestore.collection(_collection).doc(sellerId).update(updates);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Change password
  Future<Map<String, dynamic>> changePassword({
    required String sellerId,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final doc = await _firestore.collection(_collection).doc(sellerId).get();
      if (!doc.exists) {
        return {
          'success': false,
          'message': 'Seller not found',
        };
      }

      final sellerData = doc.data()!;
      final oldHashedPassword = _hashPassword(oldPassword);

      if (sellerData['passwordHash'] != oldHashedPassword) {
        return {
          'success': false,
          'message': 'Current password is incorrect',
        };
      }

      final newHashedPassword = _hashPassword(newPassword);
      await _firestore
          .collection(_collection)
          .doc(sellerId)
          .update({'passwordHash': newHashedPassword});

      return {
        'success': true,
        'message': 'Password changed successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to change password: $e',
      };
    }
  }
}
