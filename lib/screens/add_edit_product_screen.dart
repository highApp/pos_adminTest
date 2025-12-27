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

  late TextEditingController _nameController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _salePriceController;
  late TextEditingController _percentageController;
  late TextEditingController _wholesalePriceController;
  late TextEditingController _wholesalePercentageController;
  late TextEditingController _stockController;
  late TextEditingController _valueController;
  late TextEditingController _unitController;
  late TextEditingController _barcodeController;
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
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _purchasePriceController =
        TextEditingController(text: widget.product?.purchasePrice.toString() ?? '');
    _salePriceController =
        TextEditingController(text: widget.product?.salePrice.toString() ?? '');
    _percentageController = TextEditingController();
    _wholesalePriceController =
        TextEditingController(text: widget.product?.wholesalePrice?.toString() ?? '');
    _wholesalePercentageController = TextEditingController();
    _stockController =
        TextEditingController(text: widget.product?.stock.toString() ?? '');
    _valueController =
        TextEditingController(text: widget.product?.value?.toString() ?? '');
    _unitController =
        TextEditingController(text: widget.product?.unit ?? '');
    _barcodeController =
        TextEditingController(text: widget.product?.barcode ?? '');
    _selectedCategory = widget.product?.category ?? 'General';
    _imageUrl = widget.product?.imageUrl;
    // Category field is disabled by default when editing a product
    _isCategoryFieldEnabled = widget.product == null;
    
    foundation.debugPrint('=== Edit Product Screen Initialized ===');
    foundation.debugPrint('Product: ${widget.product?.name}');
    foundation.debugPrint('Image URL from database: $_imageUrl');
    
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _percentageController.dispose();
    _wholesalePriceController.dispose();
    _wholesalePercentageController.dispose();
    _stockController.dispose();
    _valueController.dispose();
    _unitController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  bool _isUpdatingFromPercentage = false;
  bool _isUpdatingFromSalePrice = false;
  bool _isUpdatingFromWholesalePercentage = false;
  bool _isUpdatingFromWholesalePrice = false;

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
      
      final product = Product(
        id: productId,
        name: _nameController.text.trim(),
        description: widget.product?.description,
        purchasePrice: double.parse(_purchasePriceController.text),
        salePrice: double.parse(_salePriceController.text),
        wholesalePrice: _wholesalePriceController.text.trim().isEmpty
            ? null
            : double.tryParse(_wholesalePriceController.text.trim()),
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
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Product Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.shopping_bag),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter product name';
                }
                return null;
              },
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
                } else if (widget.product == null && categoryNames.isEmpty) {
                  _selectedCategory = 'General';
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

                // Build dropdown with existing category included if not in list
                final allCategoryNames = categoryNames.contains(_selectedCategory)
                    ? categoryNames
                    : [_selectedCategory, ...categoryNames];

                return Stack(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Category *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.category),
                        suffixIcon: _isCategoryFieldEnabled
                            ? const Icon(Icons.lock_open, color: Colors.green)
                            : const Icon(Icons.lock, color: Colors.grey),
                        hintText: _isCategoryFieldEnabled ? null : 'Click anywhere to enable',
                      ),
                      items: allCategoryNames.map<DropdownMenuItem<String>>((category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Row(
                            children: [
                              Text(category),
                              if (!categoryNames.contains(category))
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    '(Legacy)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _isCategoryFieldEnabled
                          ? (value) {
                              setState(() {
                                _selectedCategory = value!;
                              });
                            }
                          : null,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a category';
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
                        // Check if sale price is less than purchase price
                        final purchasePrice = double.tryParse(_purchasePriceController.text);
                        if (purchasePrice != null && purchasePrice > 0 && salePrice < purchasePrice) {
                          return 'Sale price cannot be less than purchase price (Rs. ${purchasePrice.toStringAsFixed(2)})';
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
                  // Check if sale price is less than purchase price
                  final purchasePrice = double.tryParse(_purchasePriceController.text);
                  if (purchasePrice != null && purchasePrice > 0 && salePrice < purchasePrice) {
                    return 'Sale price cannot be less than purchase price (Rs. ${purchasePrice.toStringAsFixed(2)})';
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

