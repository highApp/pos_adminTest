import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';

class ProductService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'products';

  // Get all products stream
  Stream<List<Product>> getProductsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Product.fromMap(doc.data());
      }).toList();
    });
  }

  // Get products by category
  Stream<List<Product>> getProductsByCategory(String category) {
    return _firestore
        .collection(_collection)
        .where('category', isEqualTo: category)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Product.fromMap(doc.data());
      }).toList();
    });
  }

  // Search products
  Future<List<Product>> searchProducts(String query) async {
    final snapshot = await _firestore.collection(_collection).get();
    final products = snapshot.docs.map((doc) => Product.fromMap(doc.data())).toList();
    
    return products.where((product) {
      final searchQuery = query.toLowerCase();
      
      // Search in display name (backward compatible)
      if (product.displayName.toLowerCase().contains(searchQuery)) {
        return true;
      }
      
      // Search in all language names
      if (product.names != null) {
        for (final name in product.names!.values) {
          if (name.toLowerCase().contains(searchQuery)) {
            return true;
          }
        }
      }
      
      // Search in barcode and description
      if (product.barcode?.toLowerCase().contains(searchQuery) ?? false) {
        return true;
      }
      if (product.description?.toLowerCase().contains(searchQuery) ?? false) {
        return true;
      }
      
      return false;
    }).toList();
  }

  // Add product
  Future<void> addProduct(Product product) async {
    await _firestore.collection(_collection).doc(product.id).set(product.toMap());
  }

  // Update product
  Future<void> updateProduct(Product product) async {
    final updatedProduct = product.copyWith(updatedAt: DateTime.now());
    await _firestore
        .collection(_collection)
        .doc(product.id)
        .update(updatedProduct.toMap());
  }

  // Delete product
  Future<void> deleteProduct(String productId) async {
    await _firestore.collection(_collection).doc(productId).delete();
  }

  // Update stock
  Future<void> updateStock(String productId, double quantity) async {
    final docRef = _firestore.collection(_collection).doc(productId);
    final doc = await docRef.get();
    
    if (!doc.exists) {
      throw Exception('Product not found: $productId');
    }
    
    final product = Product.fromMap(doc.data()!);
    final newStock = product.stock + quantity;
    
    print('Updating stock for ${product.displayName}: ${product.stock} + $quantity = $newStock');
    
    final updatedProduct = product.copyWith(
      stock: newStock,
      updatedAt: DateTime.now(),
    );
    
    await docRef.update(updatedProduct.toMap());
    print('Stock updated successfully in database');
  }

  // Decrease stock (used during sale)
  Future<bool> decreaseStock(String productId, double quantity) async {
    final docRef = _firestore.collection(_collection).doc(productId);
    final doc = await docRef.get();
    
    if (doc.exists) {
      final product = Product.fromMap(doc.data()!);
      if (product.stock >= quantity) {
        final updatedProduct = product.copyWith(
          stock: product.stock - quantity,
          updatedAt: DateTime.now(),
        );
        await docRef.update(updatedProduct.toMap());
        return true;
      }
    }
    return false;
  }

  // Get product by ID
  Future<Product?> getProductById(String productId) async {
    final doc = await _firestore.collection(_collection).doc(productId).get();
    if (doc.exists) {
      return Product.fromMap(doc.data()!);
    }
    return null;
  }

  // Get low stock products
  Stream<List<Product>> getLowStockProducts(int threshold) {
    return _firestore
        .collection(_collection)
        .where('stock', isLessThanOrEqualTo: threshold)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Product.fromMap(doc.data());
      }).toList();
    });
  }
}

