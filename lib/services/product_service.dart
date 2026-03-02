import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';

class ProductService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'products';
  List<Product>? _productListCache;
  DateTime? _productListCacheTime;
  static const _searchCacheDuration = Duration(seconds: 60);

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

  // Search products (cached 60s so Add Item search doesn't hit Firestore every keystroke)
  Future<List<Product>> searchProducts(String query) async {
    final now = DateTime.now();
    if (_productListCache != null &&
        _productListCacheTime != null &&
        now.difference(_productListCacheTime!) < _searchCacheDuration) {
      return _filterProductsByQuery(_productListCache!, query);
    }
    final snapshot = await _firestore.collection(_collection).get();
    final products = snapshot.docs.map((doc) => Product.fromMap(doc.data())).toList();
    _productListCache = products;
    _productListCacheTime = now;
    return _filterProductsByQuery(products, query);
  }

  List<Product> _filterProductsByQuery(List<Product> products, String query) {
    final searchQuery = query.toLowerCase();
    if (searchQuery.isEmpty) return products;
    return products.where((product) {
      if (product.displayName.toLowerCase().contains(searchQuery)) return true;
      if (product.names != null) {
        for (final name in product.names!.values) {
          if (name.toLowerCase().contains(searchQuery)) return true;
        }
      }
      if (product.barcode?.toLowerCase().contains(searchQuery) ?? false) return true;
      if (product.productCode?.toLowerCase().contains(searchQuery) ?? false) return true;
      if (product.description?.toLowerCase().contains(searchQuery) ?? false) return true;
      return false;
    }).toList();
  }

  void _invalidateSearchCache() {
    _productListCache = null;
    _productListCacheTime = null;
  }

  // Add product
  Future<void> addProduct(Product product) async {
    await _firestore.collection(_collection).doc(product.id).set(product.toMap());
    _invalidateSearchCache();
  }

  // Update product
  Future<void> updateProduct(Product product) async {
    final updatedProduct = product.copyWith(updatedAt: DateTime.now());
    await _firestore
        .collection(_collection)
        .doc(product.id)
        .update(updatedProduct.toMap());
    _invalidateSearchCache();
  }

  // Delete product
  Future<void> deleteProduct(String productId) async {
    await _firestore.collection(_collection).doc(productId).delete();
    _invalidateSearchCache();
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

