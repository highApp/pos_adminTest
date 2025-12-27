import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' as foundation;
import '../models/category.dart' as category_model;

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'categories';

  // Get all active categories stream
  Stream<List<category_model.Category>> getCategoriesStream() {
    return _firestore
        .collection(_collection)
        .snapshots()
        .map((snapshot) {
      final categories = snapshot.docs
          .map((doc) {
            try {
              return category_model.Category.fromMap(doc.data());
            } catch (e) {
              foundation.debugPrint('Error parsing category ${doc.id}: $e');
              return null;
            }
          })
          .where((category) => category != null && category.isActive)
          .cast<category_model.Category>()
          .toList();
      
      // Sort by name
      categories.sort((a, b) => a.name.compareTo(b.name));
      return categories;
    }).handleError((error) {
      foundation.debugPrint('Error in getCategoriesStream: $error');
      return <category_model.Category>[];
    });
  }

  // Get all categories (including inactive) - for admin management
  Stream<List<category_model.Category>> getAllCategoriesStream() {
    return _firestore
        .collection(_collection)
        .snapshots()
        .map((snapshot) {
      final categories = snapshot.docs
          .map((doc) {
            try {
              return category_model.Category.fromMap(doc.data());
            } catch (e) {
              foundation.debugPrint('Error parsing category ${doc.id}: $e');
              return null;
            }
          })
          .where((category) => category != null)
          .cast<category_model.Category>()
          .toList();
      
      // Sort by name
      categories.sort((a, b) => a.name.compareTo(b.name));
      return categories;
    }).handleError((error) {
      foundation.debugPrint('Error in getAllCategoriesStream: $error');
      return <category_model.Category>[];
    });
  }

  // Get category by ID
  Future<category_model.Category?> getCategoryById(String categoryId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(categoryId).get();
      if (doc.exists) {
        return category_model.Category.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      foundation.debugPrint('Error getting category: $e');
      return null;
    }
  }

  // Add category
  Future<void> addCategory(category_model.Category category) async {
    await _firestore.collection(_collection).doc(category.id).set(category.toMap());
  }

  // Update category
  Future<void> updateCategory(category_model.Category category) async {
    final updatedCategory = category.copyWith(updatedAt: DateTime.now());
    await _firestore
        .collection(_collection)
        .doc(category.id)
        .update(updatedCategory.toMap());
  }

  // Delete category (soft delete)
  Future<void> deleteCategory(String categoryId) async {
    await _firestore.collection(_collection).doc(categoryId).update({
      'isActive': false,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  // Check if category is used by any products
  Future<bool> isCategoryInUse(String categoryName) async {
    try {
      final snapshot = await _firestore
          .collection('products')
          .where('category', isEqualTo: categoryName)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      foundation.debugPrint('Error checking category usage: $e');
      return false;
    }
  }
}
