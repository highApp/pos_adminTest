import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import '../utils/urdu_input_hint_stub.dart' if (dart.library.html) '../utils/urdu_input_hint_web.dart' as urdu_hint;

class AddEditProductScreen extends StatefulWidget {
  final Product? product;

  const AddEditProductScreen({super.key, this.product});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _productService = ProductService();
  final _categoryService = CategoryService();

  late TextEditingController _nameEnController;
  late TextEditingController _nameUrController;
  late TextEditingController _nameArController;
  late FocusNode _nameUrFocusNode;
  late TextEditingController _purchasePriceController;
  late TextEditingController _minimumSalePriceController;
  late TextEditingController _salePriceController;
  late TextEditingController _percentageController;
  late TextEditingController _wholesalePriceController;
  late TextEditingController _wholesalePercentageController;
  late TextEditingController _dozenPriceController;
  late TextEditingController _bundlePriceController;
  late TextEditingController _bundleSizeController;
  late TextEditingController _stockController;
  late TextEditingController _valueController;
  late TextEditingController _unitController;
  late TextEditingController _barcodeController;
  late TextEditingController _productCodeController;
  late TextEditingController _categoryController;
  String _selectedCategory = 'General';
  bool _usePercentage = false; // Toggle between manual and percentage mode for sale price
  bool _useWholesalePercentage = false; // Toggle between manual and percentage mode for wholesale price
  bool _isUnitFieldEnabled = false; // Unit field is disabled by default, requires password to enable
  bool _isCategoryFieldEnabled = true; // Category field enabled by default, disabled when editing product

  bool _isLoading = false;
  XFile? _selectedImage;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    // Initialize name controllers from product names or fallback to old name field
    final productNames = widget.product?.names;
    _nameEnController = TextEditingController(
      text: productNames?['en'] ?? widget.product?.name ?? ''
    );
    _nameUrController = TextEditingController(
      text: productNames?['ur'] ?? ''
    );
    _nameArController = TextEditingController(
      text: productNames?['ar'] ?? ''
    );
    _purchasePriceController =
        TextEditingController(text: widget.product?.purchasePrice.toString() ?? '');
    _minimumSalePriceController = TextEditingController(
        text: widget.product?.minimumSalePrice?.toString() ?? '');
    _salePriceController =
        TextEditingController(text: widget.product?.salePrice.toString() ?? '');
    _percentageController = TextEditingController();
    _wholesalePriceController =
        TextEditingController(text: widget.product?.wholesalePrice?.toString() ?? '');
    _wholesalePercentageController = TextEditingController();
    _dozenPriceController =
        TextEditingController(text: widget.product?.dozenPrice?.toString() ?? '');
    _bundlePriceController =
        TextEditingController(text: widget.product?.bundlePrice?.toString() ?? '');
    _bundleSizeController =
        TextEditingController(text: widget.product?.bundleSize?.toString() ?? '');
    _stockController =
        TextEditingController(text: widget.product?.stock.toString() ?? '');
    _valueController =
        TextEditingController(text: widget.product?.value?.toString() ?? '');
    _unitController =
        TextEditingController(text: widget.product?.unit ?? '');
    _barcodeController =
        TextEditingController(text: widget.product?.barcode ?? '');
    _productCodeController =
        TextEditingController(text: widget.product?.productCode ?? '');
    _selectedCategory = widget.product?.category ?? 'General';
    _categoryController = TextEditingController(text: _selectedCategory);
    _imageUrl = widget.product?.imageUrl;
    // Category field is disabled by default when editing a product
    _isCategoryFieldEnabled = widget.product == null;
    
    foundation.debugPrint('=== Edit Product Screen Initialized ===');
    foundation.debugPrint('Product: ${widget.product?.displayName}');
    foundation.debugPrint('Image URL from database: $_imageUrl');
    
    _nameUrFocusNode = FocusNode();
    _nameUrFocusNode.addListener(_onUrduFieldFocusChange);

    // Add listeners to auto-update sale price
    _purchasePriceController.addListener(_updateSalePriceFromPercentage);
    _percentageController.addListener(_updateSalePriceFromPercentage);
    // Add listener to update percentage when sale price is edited
    _salePriceController.addListener(_updatePercentageFromSalePrice);
    
    // Add listeners to auto-update wholesale price
    _purchasePriceController.addListener(_updateWholesalePriceFromPercentage);
    _wholesalePercentageController.addListener(_updateWholesalePriceFromPercentage);
    // Add listener to update percentage when wholesale price is edited
    _wholesalePriceController.addListener(_updatePercentageFromWholesalePrice);

    // Bundle ↔ Wholesale real-time sync: bundle price = wholesale × bundle size
    _wholesalePriceController.addListener(_updateBundlePriceFromWholesale);
    _bundleSizeController.addListener(_updateBundlePriceFromWholesale);
    _bundlePriceController.addListener(_updateWholesalePriceFromBundle);
    // Dozen ↔ Wholesale real-time sync: dozen price = wholesale × 12
    _wholesalePriceController.addListener(_updateDozenPriceFromWholesale);
    _dozenPriceController.addListener(_updateWholesalePriceFromDozen);
  }

  void _onUrduFieldFocusChange() {
    if (_nameUrFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        urdu_hint.setUrduInputHint();
      });
    }
  }

  @override
  void dispose() {
    _nameUrFocusNode.removeListener(_onUrduFieldFocusChange);
    _nameUrFocusNode.dispose();
    _nameEnController.dispose();
    _nameUrController.dispose();
    _nameArController.dispose();
    _purchasePriceController.dispose();
    _minimumSalePriceController.dispose();
    _salePriceController.dispose();
    _percentageController.dispose();
    _wholesalePriceController.dispose();
    _wholesalePercentageController.dispose();
    _dozenPriceController.dispose();
    _bundlePriceController.dispose();
    _bundleSizeController.dispose();
    _stockController.dispose();
    _valueController.dispose();
    _unitController.dispose();
    _barcodeController.dispose();
    _productCodeController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  bool _isUpdatingFromPercentage = false;
  bool _isUpdatingFromSalePrice = false;
  bool _isUpdatingFromWholesalePercentage = false;
  bool _isUpdatingFromWholesalePrice = false;
  bool _isUpdatingBundleFromWholesale = false;
  bool _isUpdatingWholesaleFromBundle = false;
  bool _isUpdatingDozenFromWholesale = false;
  bool _isUpdatingWholesaleFromDozen = false;

  /// Effective floor for sale price: Minimum Sale Price if set and > 0, else Purchase Price.
  double? _getEffectiveMinSalePrice() {
    final purchasePrice = double.tryParse(_purchasePriceController.text);
    final minSale = double.tryParse(_minimumSalePriceController.text.trim());
    if (minSale != null && minSale > 0) return minSale;
    return purchasePrice;
  }

  void _updateSalePriceFromPercentage() {
    if (_usePercentage && !_isUpdatingFromSalePrice && _purchasePriceController.text.isNotEmpty) {
      final purchasePrice = double.tryParse(_purchasePriceController.text);
      if (purchasePrice != null && purchasePrice > 0) {
        final percentageText = _percentageController.text.replaceAll('%', '').trim();
        if (percentageText.isNotEmpty) {
          final percentage = double.tryParse(percentageText);
          if (percentage != null && percentage >= 0) {
            // Calculate: Sale Price = Purchase Price * (1 + percentage/100)
            // Example: 200 * (1 + 5/100) = 200 * 1.05 = 210
            _isUpdatingFromPercentage = true;
            final calculatedSalePrice = purchasePrice * (1 + percentage / 100);
            _salePriceController.text = calculatedSalePrice.toStringAsFixed(2);
            _isUpdatingFromPercentage = false;
          } else {
            // If percentage is invalid, clear sale price
            if (!_isUpdatingFromSalePrice) {
              _salePriceController.clear();
            }
          }
        } else {
          // If percentage field is empty, don't clear sale price (user might be editing it)
        }
      }
    }
  }

  void _updatePercentageFromSalePrice() {
    if (_usePercentage && !_isUpdatingFromPercentage && _purchasePriceController.text.isNotEmpty && _salePriceController.text.isNotEmpty) {
      final purchasePrice = double.tryParse(_purchasePriceController.text);
      final salePrice = double.tryParse(_salePriceController.text);
      if (purchasePrice != null && salePrice != null && purchasePrice > 0) {
        // Calculate: Percentage = ((Sale Price - Purchase Price) / Purchase Price) * 100
        // Example: ((220 - 200) / 200) * 100 = 10%
        _isUpdatingFromSalePrice = true;
        final calculatedPercentage = ((salePrice - purchasePrice) / purchasePrice) * 100;
        _percentageController.text = calculatedPercentage.toStringAsFixed(2);
        _isUpdatingFromSalePrice = false;
      }
    }
  }

  void _updateWholesalePriceFromPercentage() {
    if (_useWholesalePercentage && !_isUpdatingFromWholesalePrice && _purchasePriceController.text.isNotEmpty) {
      final purchasePrice = double.tryParse(_purchasePriceController.text);
      if (purchasePrice != null && purchasePrice > 0) {
        final percentageText = _wholesalePercentageController.text.replaceAll('%', '').trim();
        if (percentageText.isNotEmpty) {
          final percentage = double.tryParse(percentageText);
          if (percentage != null && percentage >= 0) {
            // Calculate: Wholesale Price = Purchase Price * (1 + percentage/100)
            _isUpdatingFromWholesalePercentage = true;
            final calculatedWholesalePrice = purchasePrice * (1 + percentage / 100);
            _wholesalePriceController.text = calculatedWholesalePrice.toStringAsFixed(2);
            _isUpdatingFromWholesalePercentage = false;
          } else {
            // If percentage is invalid, clear wholesale price
            if (!_isUpdatingFromWholesalePrice) {
              _wholesalePriceController.clear();
            }
          }
        }
      }
    }
  }

  void _updatePercentageFromWholesalePrice() {
    if (_useWholesalePercentage && !_isUpdatingFromWholesalePercentage && _purchasePriceController.text.isNotEmpty && _wholesalePriceController.text.isNotEmpty) {
      final purchasePrice = double.tryParse(_purchasePriceController.text);
      final wholesalePrice = double.tryParse(_wholesalePriceController.text);
      if (purchasePrice != null && wholesalePrice != null && purchasePrice > 0) {
        // Calculate: Percentage = ((Wholesale Price - Purchase Price) / Purchase Price) * 100
        _isUpdatingFromWholesalePrice = true;
        final calculatedPercentage = ((wholesalePrice - purchasePrice) / purchasePrice) * 100;
        _wholesalePercentageController.text = calculatedPercentage.toStringAsFixed(2);
        _isUpdatingFromWholesalePrice = false;
      }
    }
  }

  /// When wholesale price changes: dozen price = wholesale × 12. Skip if wholesale was set from bundle (keep dozen separate).
  void _updateDozenPriceFromWholesale() {
    if (_isUpdatingWholesaleFromDozen || _isUpdatingWholesaleFromBundle) return;
    final wholesale = double.tryParse(_wholesalePriceController.text.trim());
    if (wholesale != null && wholesale > 0) {
      _isUpdatingDozenFromWholesale = true;
      _dozenPriceController.text = (wholesale * 12).toStringAsFixed(2);
      _isUpdatingDozenFromWholesale = false;
    }
  }

  /// When dozen price changes: wholesale price = dozen price / 12. Do not change bundle (dozen and bundle are separate).
  void _updateWholesalePriceFromDozen() {
    if (_isUpdatingDozenFromWholesale) return;
    final dozen = double.tryParse(_dozenPriceController.text.trim());
    if (dozen != null && dozen > 0) {
      _isUpdatingWholesaleFromDozen = true;
      _wholesalePriceController.text = (dozen / 12).toStringAsFixed(2);
      _isUpdatingWholesaleFromDozen = false;
      _updatePercentageFromWholesalePrice();
      // Do not update bundle — dozen and bundle are independent
    }
  }

  /// When wholesale price or bundle size changes: bundle price = wholesale × bundle size. Skip if wholesale was set from dozen (keep bundle separate).
  void _updateBundlePriceFromWholesale() {
    if (_isUpdatingWholesaleFromBundle || _isUpdatingWholesaleFromDozen) return;
    final wholesale = double.tryParse(_wholesalePriceController.text.trim());
    final sizeStr = _bundleSizeController.text.trim();
    final size = sizeStr.isEmpty ? null : int.tryParse(sizeStr);
    if (wholesale != null && wholesale > 0 && size != null && size > 0) {
      _isUpdatingBundleFromWholesale = true;
      _bundlePriceController.text = (wholesale * size).toStringAsFixed(2);
      _isUpdatingBundleFromWholesale = false;
    }
  }

  /// When bundle price changes: wholesale price = bundle price / bundle size. Do not change dozen (bundle and dozen are separate).
  void _updateWholesalePriceFromBundle() {
    if (_isUpdatingBundleFromWholesale) return;
    final bundlePrice = double.tryParse(_bundlePriceController.text.trim());
    final sizeStr = _bundleSizeController.text.trim();
    final size = sizeStr.isEmpty ? null : int.tryParse(sizeStr);
    if (bundlePrice != null && bundlePrice > 0 && size != null && size > 0) {
      _isUpdatingWholesaleFromBundle = true;
      _wholesalePriceController.text = (bundlePrice / size).toStringAsFixed(2);
      _isUpdatingWholesaleFromBundle = false;
      _updatePercentageFromWholesalePrice();
      // Do not update dozen — bundle and dozen are independent
    }
  }

  Future<void> _pickImage() async {
    try {
      foundation.debugPrint('Opening image picker...');
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        foundation.debugPrint('Image selected: ${image.path}');
        setState(() {
          _selectedImage = image;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image selected! Click Save to upload.'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } else {
        foundation.debugPrint('No image selected');
      }
    } catch (e) {
      foundation.debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage(String productId) async {
    if (_selectedImage == null) {
      foundation.debugPrint('No image selected, returning existing URL: $_imageUrl');
      return _imageUrl;
    }

    try {
      foundation.debugPrint('Starting image upload for product: $productId');
      
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('product_images')
          .child('$productId.jpg');

      // Upload file with metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'productId': productId},
      );

      UploadTask uploadTask;
      
      if (foundation.kIsWeb) {
        foundation.debugPrint('Uploading image for web...');
        final bytes = await _selectedImage!.readAsBytes();
        foundation.debugPrint('Image bytes read: ${bytes.length} bytes');
        uploadTask = storageRef.putData(bytes, metadata);
      } else {
        foundation.debugPrint('Uploading image for mobile...');
        uploadTask = storageRef.putFile(File(_selectedImage!.path), metadata);
      }

      // Wait for upload to complete
      final snapshot = await uploadTask.whenComplete(() {
        foundation.debugPrint('Upload task completed');
      });
      
      foundation.debugPrint('Upload state: ${snapshot.state}');
      
      if (snapshot.state != TaskState.success) {
        throw Exception('Upload failed with state: ${snapshot.state}');
      }

      // Get download URL
      final downloadUrl = await storageRef.getDownloadURL();
      foundation.debugPrint('Image uploaded successfully! URL: $downloadUrl');
      
      // Verify the URL is accessible
      foundation.debugPrint('Verifying URL is accessible...');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Image uploaded! URL: ${downloadUrl.substring(0, 50)}...'),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      return downloadUrl;
    } catch (e, stackTrace) {
      foundation.debugPrint('Error uploading image: $e');
      foundation.debugPrint('Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Image upload failed!'),
                Text('Error: $e', style: const TextStyle(fontSize: 12)),
              ],
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      throw e; // Re-throw to prevent saving with broken URL
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _imageUrl = null;
    });
  }

  Future<bool> _showPasswordDialog(String fieldName) async {
    if (!mounted) return false;
    
    final passwordController = TextEditingController();
    String? errorMessage;
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Enter Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      hintText: 'Enter password to enable $fieldName',
                      errorText: errorMessage,
                    ),
                    autofocus: true,
                    onSubmitted: (value) {
                      if (value == '5202') {
                        Navigator.of(dialogContext).pop(true);
                      } else {
                        setDialogState(() {
                          errorMessage = 'Incorrect password';
                        });
                      }
                    },
                    onChanged: (value) {
                      if (errorMessage != null) {
                        setDialogState(() {
                          errorMessage = null;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (passwordController.text == '5202') {
                      Navigator.of(dialogContext).pop(true);
                    } else {
                      setDialogState(() {
                        errorMessage = 'Incorrect password';
                      });
                    }
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    // Wait a frame before disposing to ensure dialog is fully closed
    await Future.delayed(const Duration(milliseconds: 100));
    passwordController.dispose();
    
    return result == true;
  }

  Future<void> _showUnitPasswordDialog() async {
    final result = await _showPasswordDialog('unit field');
    if (result && mounted) {
      setState(() {
        _isUnitFieldEnabled = true;
      });
    }
  }

  Future<void> _showCategoryPasswordDialog() async {
    final result = await _showPasswordDialog('category field');
    if (result && mounted) {
      setState(() {
        _isCategoryFieldEnabled = true;
      });
    }
  }

  void _showCategorySearchSheet(
    BuildContext context,
    List<String> allCategoryNames,
    List<String> categoryNames,
  ) {
    final searchController = TextEditingController();
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = searchQuery.isEmpty
                ? allCategoryNames
                : allCategoryNames
                    .where((c) =>
                        c.toLowerCase().contains(searchQuery.toLowerCase()))
                    .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                // Give Column a bounded height so Expanded/ListView don't cause RenderFlex
                // (unbounded height) on Android.
                final sheetHeight = MediaQuery.of(context).size.height * 0.6;
                return SizedBox(
                  height: sheetHeight,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: 'Search categories...',
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (value) {
                            setSheetState(() {
                              searchQuery = value;
                            });
                          },
                          autofocus: true,
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                          final name = filtered[index];
                          final isSelected = name == _selectedCategory;
                          return ListTile(
                            leading: Icon(
                              isSelected ? Icons.check_circle : Icons.category_outlined,
                              color: isSelected ? Theme.of(context).primaryColor : null,
                            ),
                            title: Text(name),
                            onTap: () {
                              // Update state BEFORE popping to avoid _dependents.isEmpty
                              // assertion on Android (setState after pop causes the crash).
                              if (mounted) {
                                setState(() {
                                  _selectedCategory = name;
                                  _categoryController.text = name;
                                });
                              }
                              Navigator.of(sheetContext).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                );
              },
            );
          },
        );
      },
    ).then((_) {
      searchController.dispose();
    });
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final productId = widget.product?.id ?? const Uuid().v4();
      foundation.debugPrint('=== Saving Product ===');
      foundation.debugPrint('Product ID: $productId');
      foundation.debugPrint('Is Edit Mode: ${widget.product != null}');
      foundation.debugPrint('Selected Image: ${_selectedImage != null ? "Yes" : "No"}');
      foundation.debugPrint('Existing Image URL: $_imageUrl');
      
      // Upload image if selected
      String? uploadedImageUrl;
      try {
        uploadedImageUrl = await _uploadImage(productId);
        foundation.debugPrint('Final Image URL to save: $uploadedImageUrl');
      } catch (e) {
        foundation.debugPrint('Image upload failed, not saving product: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot save: Image upload failed. Please try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return; // Don't save product if image upload fails
      }
      
      // Build names map from the three language fields
      final Map<String, String> namesMap = {};
      if (_nameEnController.text.trim().isNotEmpty) {
        namesMap['en'] = _nameEnController.text.trim();
      }
      if (_nameUrController.text.trim().isNotEmpty) {
        namesMap['ur'] = _nameUrController.text.trim();
      }
      if (_nameArController.text.trim().isNotEmpty) {
        namesMap['ar'] = _nameArController.text.trim();
      }
      
      final product = Product(
        id: productId,
        names: namesMap.isNotEmpty ? namesMap : null,
        name: namesMap.isNotEmpty ? null : _nameEnController.text.trim(), // Fallback for backward compatibility
        description: widget.product?.description,
        purchasePrice: double.parse(_purchasePriceController.text),
        minimumSalePrice: _minimumSalePriceController.text.trim().isEmpty
            ? null
            : double.tryParse(_minimumSalePriceController.text.trim()),
        salePrice: double.parse(_salePriceController.text),
        wholesalePrice: _wholesalePriceController.text.trim().isEmpty
            ? null
            : double.tryParse(_wholesalePriceController.text.trim()),
        dozenPrice: _dozenPriceController.text.trim().isEmpty
            ? null
            : double.tryParse(_dozenPriceController.text.trim()),
        bundlePrice: _bundlePriceController.text.trim().isEmpty
            ? null
            : double.tryParse(_bundlePriceController.text.trim()),
        bundleSize: _bundleSizeController.text.trim().isEmpty
            ? null
            : int.tryParse(_bundleSizeController.text.trim()),
        stock: double.parse(_stockController.text),
        unit: _unitController.text.trim().isEmpty 
            ? 'pieces' 
            : _unitController.text.trim(),
        value: _valueController.text.trim().isEmpty
            ? null
            : double.tryParse(_valueController.text.trim()),
        barcode: _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        productCode: _productCodeController.text.trim().isEmpty
            ? null
            : _productCodeController.text.trim(),
        category: _selectedCategory,
        imageUrl: uploadedImageUrl,
        createdAt: widget.product?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      foundation.debugPrint('Saving product to Firestore...');
      if (widget.product == null) {
        await _productService.addProduct(product);
        foundation.debugPrint('Product added successfully');
      } else {
        await _productService.updateProduct(product);
        foundation.debugPrint('Product updated successfully');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.product == null
                  ? 'Product added successfully'
                  : 'Product updated successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'Add Product' : 'Edit Product'),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Product Names Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.language, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Text(
                        'Product Names *',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameEnController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name (English) *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.language, color: Colors.blue),
                      helperText: 'Required',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter English name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameUrController,
                    focusNode: _nameUrFocusNode,
                    decoration: const InputDecoration(
                      labelText: 'Product Name (Urdu)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.language, color: Colors.green),
                      helperText: 'Optional. Tap here then switch to Urdu keyboard (e.g. globe key) to type in Urdu.',
                    ),
                    textDirection: TextDirection.rtl,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameArController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name (Arabic)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.language, color: Colors.orange),
                      helperText: 'Optional',
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Product Code / Item Code (Optional)
            TextFormField(
              controller: _productCodeController,
              decoration: const InputDecoration(
                labelText: 'Product Code / Item Code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag, color: Colors.grey),
                helperText: 'Optional. Your internal code or SKU for this product.',
              ),
            ),
            const SizedBox(height: 16),
            // Product Image Section (Optional)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.image, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Text(
                        'Product Image (Optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Show current or selected image
                  if (_selectedImage != null || _imageUrl != null)
                    Column(
                      children: [
                        Container(
                          height: 150,
                          width: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _selectedImage != null
                                ? (foundation.kIsWeb
                                    ? Image.network(
                                        _selectedImage!.path,
                                        fit: BoxFit.cover,
                                      )
                                    : Image.file(
                                        File(_selectedImage!.path),
                                        fit: BoxFit.cover,
                                      ))
                                : (_imageUrl != null
                                    ? Image.network(
                                        _imageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          foundation.debugPrint('=== IMAGE LOAD ERROR ===');
                                          foundation.debugPrint('Image URL: $_imageUrl');
                                          foundation.debugPrint('Error: $error');
                                          foundation.debugPrint('StackTrace: $stackTrace');
                                          return Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.broken_image, size: 40, color: Colors.red),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Failed to load',
                                                style: TextStyle(fontSize: 10, color: Colors.red[700]),
                                              ),
                                              Text(
                                                'Check console',
                                                style: TextStyle(fontSize: 8, color: Colors.grey[600]),
                                              ),
                                            ],
                                          );
                                        },
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            foundation.debugPrint('Image loaded successfully: $_imageUrl');
                                            return child;
                                          }
                                          foundation.debugPrint('Loading image: $_imageUrl');
                                          return const Center(
                                            child: CircularProgressIndicator(),
                                          );
                                        },
                                      )
                                    : const Center(child: Icon(Icons.image, size: 50))),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Change'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _removeImage,
                              icon: const Icon(Icons.delete, size: 18),
                              label: const Text('Remove'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    // Show upload button if no image
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: const Text('Select Image'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            StreamBuilder(
              stream: _categoryService.getCategoriesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 60,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  foundation.debugPrint('Error loading categories: ${snapshot.error}');
                  // Show error but still allow manual entry
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Error loading categories: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Stack(
                        children: [
                          TextFormField(
                            initialValue: _selectedCategory,
                            enabled: _isCategoryFieldEnabled,
                            decoration: InputDecoration(
                              labelText: 'Category *',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.category),
                              helperText: 'Enter category name manually',
                              suffixIcon: _isCategoryFieldEnabled
                                  ? const Icon(Icons.lock_open, color: Colors.green)
                                  : const Icon(Icons.lock, color: Colors.grey),
                            ),
                            onChanged: _isCategoryFieldEnabled
                                ? (value) {
                                    _selectedCategory = value.trim().isEmpty ? 'General' : value.trim();
                                  }
                                : null,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter category name';
                              }
                              return null;
                            },
                          ),
                          if (!_isCategoryFieldEnabled)
                            Positioned.fill(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () {
                                    _showCategoryPasswordDialog();
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                }

                final categories = snapshot.data ?? [];
                final categoryNames = categories.map((c) => c.name).toList();
                
                // Preserve existing category even if not in list (for backward compatibility)
                // Only set default if this is a new product and no categories exist
                if (widget.product == null && categoryNames.isNotEmpty && !categoryNames.contains(_selectedCategory)) {
                  _selectedCategory = categoryNames.first;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _categoryController.text != _selectedCategory) {
                      _categoryController.text = _selectedCategory;
                      setState(() {});
                    }
                  });
                } else if (widget.product == null && categoryNames.isEmpty) {
                  _selectedCategory = 'General';
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _categoryController.text != _selectedCategory) {
                      _categoryController.text = _selectedCategory;
                      setState(() {});
                    }
                  });
                }

                // If no categories exist, allow manual entry for backward compatibility
                if (categoryNames.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No categories available. You can enter category name manually.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Stack(
                        children: [
                          TextFormField(
                            initialValue: _selectedCategory,
                            enabled: _isCategoryFieldEnabled,
                            decoration: InputDecoration(
                              labelText: 'Category *',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.category),
                              helperText: 'Enter category name',
                              suffixIcon: _isCategoryFieldEnabled
                                  ? const Icon(Icons.lock_open, color: Colors.green)
                                  : const Icon(Icons.lock, color: Colors.grey),
                            ),
                            onChanged: _isCategoryFieldEnabled
                                ? (value) {
                                    _selectedCategory = value.trim().isEmpty ? 'General' : value.trim();
                                  }
                                : null,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter category name';
                              }
                              return null;
                            },
                          ),
                          if (!_isCategoryFieldEnabled)
                            Positioned.fill(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () {
                                    _showCategoryPasswordDialog();
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                }

                // Autocomplete: type to filter categories in real time, no modal, no page jump
                final allCategoryNames = <String>{...categoryNames};
                if (!allCategoryNames.contains('General')) {
                  allCategoryNames.add('General');
                }
                if (!allCategoryNames.contains(_selectedCategory)) {
                  allCategoryNames.add(_selectedCategory);
                }
                final allCategoryNamesList = allCategoryNames.toList()..sort();

                return Stack(
                  children: [
                    if (_isCategoryFieldEnabled)
                      Autocomplete<String>(
                        initialValue: TextEditingValue(text: _selectedCategory),
                        optionsBuilder: (textEditingValue) {
                          final t = textEditingValue.text.toLowerCase().trim();
                          if (t.isEmpty) {
                            return foundation.SynchronousFuture(allCategoryNamesList);
                          }
                          return foundation.SynchronousFuture(
                            allCategoryNamesList
                                .where((c) => c.toLowerCase().contains(t))
                                .toList(),
                          );
                        },
                        onSelected: (value) {
                          setState(() {
                            _selectedCategory = value;
                            _categoryController.text = value;
                          });
                        },
                        fieldViewBuilder: (
                          context,
                          controller,
                          focusNode,
                          onFieldSubmitted,
                        ) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Category *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.category),
                              hintText: 'Type to search categories',
                              helperText: 'Filter and select from list',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please select a category';
                              }
                              return null;
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 220),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      dense: true,
                                      title: Text(option),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    else
                      TextFormField(
                        controller: _categoryController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Category *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                          suffixIcon: Icon(Icons.lock, color: Colors.grey),
                        ),
                        onTap: () => _showCategoryPasswordDialog(),
                      ),
                    if (!_isCategoryFieldEnabled)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => _showCategoryPasswordDialog(),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _purchasePriceController,
              decoration: const InputDecoration(
                labelText: 'Purchase Price *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.shopping_cart),
                prefixText: 'Rs. ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Enter purchase price';
                }
                if (double.tryParse(value) == null) {
                  return 'Enter valid price';
                }
                if (double.parse(value) < 0) {
                  return 'Cannot be negative';
                }
                return null;
              },
              onChanged: (value) {
                // Re-validate sale and wholesale prices when purchase price changes
                if (_formKey.currentState != null) {
                  Future.microtask(() {
                    if (_formKey.currentState != null) {
                      _formKey.currentState!.validate();
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _minimumSalePriceController,
              decoration: const InputDecoration(
                labelText: 'Minimum Sale Price',
                hintText: 'Optional. Cannot sell below this price in POS.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.sell),
                prefixText: 'Rs. ',
                helperText: 'If set, POS will not allow selling below this price. If empty, purchase price is used as floor.',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final v = double.tryParse(value.trim());
                if (v == null) return 'Enter valid price';
                if (v < 0) return 'Cannot be negative';
                return null;
              },
              onChanged: (value) {
                if (_formKey.currentState != null) {
                  Future.microtask(() {
                    if (_formKey.currentState != null) {
                      _formKey.currentState!.validate();
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            // Toggle between manual and percentage mode
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Manual'),
                        icon: Icon(Icons.edit, size: 18),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Percentage'),
                        icon: Icon(Icons.percent, size: 18),
                      ),
                    ],
                    selected: {_usePercentage},
                    onSelectionChanged: (Set<bool> newSelection) {
                      setState(() {
                        _usePercentage = newSelection.first;
                        if (_usePercentage) {
                          // Calculate percentage from current values if both exist
                          final purchasePrice = double.tryParse(_purchasePriceController.text);
                          final salePrice = double.tryParse(_salePriceController.text);
                          if (purchasePrice != null && salePrice != null && purchasePrice > 0) {
                            final percentage = ((salePrice - purchasePrice) / purchasePrice) * 100;
                            _percentageController.text = percentage.toStringAsFixed(2);
                            // Trigger calculation
                            _updateSalePriceFromPercentage();
                          } else if (purchasePrice != null && purchasePrice > 0) {
                            // If only purchase price exists, clear percentage and sale price
                            _percentageController.clear();
                            _salePriceController.clear();
                          }
                        } else {
                          _percentageController.clear();
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Show either percentage input or manual sale price input
            if (_usePercentage) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _percentageController,
                      decoration: const InputDecoration(
                        labelText: 'Profit Percentage *',
                        hintText: 'e.g., 5, 10, 15',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.percent),
                        suffixText: '%',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter percentage';
                        }
                        final percentage = double.tryParse(value);
                        if (percentage == null) {
                          return 'Enter valid percentage';
                        }
                        if (percentage < 0) {
                          return 'Cannot be negative';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _salePriceController,
                      decoration: const InputDecoration(
                        labelText: 'Sale Price *',
                        hintText: 'Auto-calculated or edit',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                        prefixText: 'Rs. ',
                        helperText: 'Edit to update percentage',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Sale price required';
                        }
                        final salePrice = double.tryParse(value);
                        if (salePrice == null) {
                          return 'Invalid price';
                        }
                        if (salePrice <= 0) {
                          return 'Must be > 0';
                        }
                        final effectiveMin = _getEffectiveMinSalePrice();
                        if (effectiveMin != null && effectiveMin > 0 && salePrice < effectiveMin) {
                          return 'Sale price cannot be less than ${_minimumSalePriceController.text.trim().isNotEmpty ? "minimum sale price" : "purchase price"} (Rs. ${effectiveMin.toStringAsFixed(2)})';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // Real-time validation as user types
                        if (_formKey.currentState != null) {
                          Future.microtask(() {
                            if (_formKey.currentState != null) {
                              _formKey.currentState!.validate();
                            }
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              TextFormField(
                controller: _salePriceController,
                decoration: const InputDecoration(
                  labelText: 'Sale Price *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                  prefixText: 'Rs. ',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter sale price';
                  }
                  final salePrice = double.tryParse(value);
                  if (salePrice == null) {
                    return 'Enter valid price';
                  }
                  if (salePrice <= 0) {
                    return 'Must be > 0';
                  }
                  final effectiveMin = _getEffectiveMinSalePrice();
                  if (effectiveMin != null && effectiveMin > 0 && salePrice < effectiveMin) {
                    return 'Sale price cannot be less than ${_minimumSalePriceController.text.trim().isNotEmpty ? "minimum sale price" : "purchase price"} (Rs. ${effectiveMin.toStringAsFixed(2)})';
                  }
                  return null;
                },
                onChanged: (value) {
                  // Real-time validation as user types
                  if (_formKey.currentState != null) {
                    Future.microtask(() {
                      if (_formKey.currentState != null) {
                        _formKey.currentState!.validate();
                      }
                    });
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            // Toggle between manual and percentage mode for wholesale price
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Manual'),
                        icon: Icon(Icons.edit, size: 18),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Percentage'),
                        icon: Icon(Icons.percent, size: 18),
                      ),
                    ],
                    selected: {_useWholesalePercentage},
                    onSelectionChanged: (Set<bool> newSelection) {
                      setState(() {
                        _useWholesalePercentage = newSelection.first;
                        if (_useWholesalePercentage) {
                          // Calculate percentage from current values if both exist
                          final purchasePrice = double.tryParse(_purchasePriceController.text);
                          final wholesalePrice = double.tryParse(_wholesalePriceController.text);
                          if (purchasePrice != null && wholesalePrice != null && purchasePrice > 0) {
                            final percentage = ((wholesalePrice - purchasePrice) / purchasePrice) * 100;
                            _wholesalePercentageController.text = percentage.toStringAsFixed(2);
                            // Trigger calculation
                            _updateWholesalePriceFromPercentage();
                          } else if (purchasePrice != null && purchasePrice > 0) {
                            // If only purchase price exists, clear percentage and wholesale price
                            _wholesalePercentageController.clear();
                            _wholesalePriceController.clear();
                          }
                        } else {
                          _wholesalePercentageController.clear();
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Show either percentage input or manual wholesale price input
            if (_useWholesalePercentage) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _wholesalePercentageController,
                      decoration: const InputDecoration(
                        labelText: 'Wholesale Profit %',
                        hintText: 'e.g., 3, 5, 8',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.percent),
                        suffixText: '%',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _wholesalePriceController,
                      decoration: const InputDecoration(
                        labelText: 'Wholesale Price',
                        hintText: 'Auto-calculated or edit',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.business),
                        prefixText: 'Rs. ',
                        helperText: 'Edit to update %',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final wholesalePrice = double.tryParse(value);
                          if (wholesalePrice == null) {
                            return 'Invalid price';
                          }
                          if (wholesalePrice <= 0) {
                            return 'Must be > 0';
                          }
                          // Check if wholesale price is less than purchase price
                          final purchasePrice = double.tryParse(_purchasePriceController.text);
                          if (purchasePrice != null && purchasePrice > 0 && wholesalePrice < purchasePrice) {
                            return 'Wholesale price cannot be less than purchase price (Rs. ${purchasePrice.toStringAsFixed(2)})';
                          }
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // Real-time validation as user types
                        if (_formKey.currentState != null) {
                          Future.microtask(() {
                            if (_formKey.currentState != null) {
                              _formKey.currentState!.validate();
                            }
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              TextFormField(
                controller: _wholesalePriceController,
                decoration: const InputDecoration(
                  labelText: 'Wholesale Price',
                  hintText: 'Optional',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                  prefixText: 'Rs. ',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final wholesalePrice = double.tryParse(value);
                    if (wholesalePrice == null) {
                      return 'Invalid price';
                    }
                    if (wholesalePrice <= 0) {
                      return 'Must be > 0';
                    }
                    // Check if wholesale price is less than purchase price
                    final purchasePrice = double.tryParse(_purchasePriceController.text);
                    if (purchasePrice != null && purchasePrice > 0 && wholesalePrice < purchasePrice) {
                      return 'Wholesale price cannot be less than purchase price (Rs. ${purchasePrice.toStringAsFixed(2)})';
                    }
                  }
                  return null;
                },
                onChanged: (value) {
                  // Real-time validation as user types
                  if (_formKey.currentState != null) {
                    Future.microtask(() {
                      if (_formKey.currentState != null) {
                        _formKey.currentState!.validate();
                      }
                    });
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _dozenPriceController,
              decoration: const InputDecoration(
                labelText: 'Dozen (Dorzan) Price',
                hintText: 'Optional (price for 12 pieces)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory_2),
                prefixText: 'Rs. ',
                helperText: 'Used in POS when Wholesale is selected (12 items = 1 dozen)',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final dozenPrice = double.tryParse(value);
                  if (dozenPrice == null) return 'Invalid price';
                  if (dozenPrice <= 0) return 'Must be > 0';
                  final purchasePrice = double.tryParse(_purchasePriceController.text);
                  // purchasePrice is per single item; dozen price must be >= 12 * purchasePrice.
                  if (purchasePrice != null &&
                      purchasePrice > 0 &&
                      dozenPrice < (purchasePrice * 12)) {
                    return 'Dozen price cannot be less than 12× purchase price (Rs. ${(purchasePrice * 12).toStringAsFixed(2)})';
                  }
                }
                return null;
              },
              onChanged: (value) {
                if (_formKey.currentState != null) {
                  Future.microtask(() {
                    if (_formKey.currentState != null) {
                      _formKey.currentState!.validate();
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _bundlePriceController,
                    decoration: const InputDecoration(
                      labelText: 'Bundle Price',
                      hintText: 'Optional (price per bundle)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.layers),
                      prefixText: 'Rs. ',
                      helperText: 'Wholesale: price per bundle',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final bundlePrice = double.tryParse(value);
                        if (bundlePrice == null) return 'Invalid price';
                        if (bundlePrice <= 0) return 'Must be > 0';
                        final sizeStr = _bundleSizeController.text.trim();
                        if (sizeStr.isEmpty) return 'Set Bundle Size';
                        final bundleSize = int.tryParse(sizeStr);
                        if (bundleSize == null || bundleSize < 1) return 'Enter a number (1 or more)';
                        final purchasePrice = double.tryParse(_purchasePriceController.text);
                        if (purchasePrice != null && purchasePrice > 0 &&
                            bundlePrice < (purchasePrice * bundleSize)) {
                          return 'Bundle price cannot be less than $bundleSize× purchase price';
                        }
                      }
                      return null;
                    },
                    onChanged: (value) {
                      if (_formKey.currentState != null) {
                        Future.microtask(() {
                          if (_formKey.currentState != null) _formKey.currentState!.validate();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _bundleSizeController,
                    decoration: const InputDecoration(
                      labelText: 'Bundle Size',
                      hintText: 'e.g. 10, 24, 36, 48, 50',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                      helperText: 'Any number (items per bundle)',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (value) {
                      if (_bundlePriceController.text.trim().isNotEmpty) {
                        if (value == null || value.isEmpty) return 'Required when Bundle Price is set';
                        final n = int.tryParse(value);
                        if (n == null || n < 1) return 'Enter a number (1 or more)';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      if (_formKey.currentState != null) {
                        Future.microtask(() {
                          if (_formKey.currentState != null) _formKey.currentState!.validate();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stockController,
              decoration: const InputDecoration(
                labelText: 'Stock Quantity *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter stock quantity';
                }
                if (double.tryParse(value) == null) {
                  return 'Please enter valid quantity';
                }
                if (double.parse(value) < 0) {
                  return 'Quantity cannot be negative';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _valueController,
                    decoration: const InputDecoration(
                      labelText: 'Product Value/Size',
                      hintText: 'e.g., 500, 1, 250',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.straighten),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: [
                      TextFormField(
                        controller: _unitController,
                        readOnly: !_isUnitFieldEnabled,
                        decoration: InputDecoration(
                          labelText: 'Unit',
                          hintText: _isUnitFieldEnabled ? 'kg, g, L, ml' : 'Click anywhere to enable',
                          border: const OutlineInputBorder(),
                          suffixIcon: _isUnitFieldEnabled
                              ? const Icon(Icons.lock_open, color: Colors.green)
                              : const Icon(Icons.lock, color: Colors.grey),
                        ),
                        textCapitalization: TextCapitalization.none,
                      ),
                      if (!_isUnitFieldEnabled)
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                _showUnitPasswordDialog();
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _barcodeController,
              decoration: const InputDecoration(
                labelText: 'Barcode',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveProduct,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(widget.product == null ? 'Add Product' : 'Update Product'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

