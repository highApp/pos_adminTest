import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cross_file/cross_file.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/seller.dart';
import '../models/due_payment.dart';
import '../providers/cart_provider.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../services/seller_service.dart';
import '../services/category_service.dart';
import '../services/printer_service.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final ProductService _productService = ProductService();
  final SalesService _salesService = SalesService();
  final CategoryService _categoryService = CategoryService();
  final TextEditingController _searchController = TextEditingController();
  List<Product>? _searchResults;
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _searchProducts(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
      });
      return;
    }

    final results = await _productService.searchProducts(query);
    setState(() {
      _searchResults = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Row(
        children: [
          // Left side - Products
          Expanded(
            flex: 3,
            child: Column(
              children: [
                // Search Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search products by name or barcode...',
                      prefixIcon: const Icon(Icons.search, color: Colors.green),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _searchProducts('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    onChanged: _searchProducts,
                  ),
                ),

                // Category Filter
                Container(
                  height: 60,
                  color: Colors.white,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: StreamBuilder(
                    stream: _categoryService.getCategoriesStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final categories = snapshot.data ?? [];
                      final categoryNames = categories.map((c) => c.name).toList();
                      
                      // Always include 'All' as first option
                      final allCategories = ['All', ...categoryNames];

                      return ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: allCategories.length,
                        itemBuilder: (context, index) {
                          final category = allCategories[index];
                          final isSelected = _selectedCategory == category;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedCategory = category;
                                });
                              },
                              selectedColor: Colors.green,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const Divider(height: 1),

                // Products Grid
                Expanded(
                  child: StreamBuilder<List<Product>>(
                    stream: _productService.getProductsStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // Get latest products from stream (always use stream as source of truth)
                      final streamProducts = snapshot.data ?? [];
                      
                      // If search results exist, merge with latest stream data to get updated stock
                      var products = _searchResults ?? streamProducts;
                      
                      // If we have search results, update them with latest stock from stream
                      // This ensures real-time stock updates even when searching
                      if (_searchResults != null && streamProducts.isNotEmpty) {
                        final productMap = {for (var p in streamProducts) p.id: p};
                        products = _searchResults!.map((searchProduct) {
                          // Always use latest product from stream if available (for real-time stock updates)
                          final latestProduct = productMap[searchProduct.id];
                          if (latestProduct != null) {
                            // Return latest product with updated stock, but keep search result's other properties
                            return latestProduct;
                          }
                          return searchProduct;
                        }).toList();
                      }
                      
                      // Filter by category
                      if (_selectedCategory != 'All') {
                        products = products
                            .where((p) => p.category == _selectedCategory)
                            .toList();
                      }
                      
                      final availableProducts =
                          products.where((p) => p.stock > 0).toList();

                      if (availableProducts.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 80, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No products available',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: availableProducts.length,
                        itemBuilder: (context, index) {
                          final product = availableProducts[index];
                          return _ProductCard(
                            product: product,
                            onTap: () {
                              context.read<CartProvider>().addItem(product);
                              // Show snackbar
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${product.name} added to cart'),
                                  duration: const Duration(milliseconds: 500),
                                  behavior: SnackBarBehavior.floating,
                                  width: 300,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right side - Cart
          Container(
            width: 420,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(-5, 0),
                ),
              ],
            ),
            child: _CartPanel(
              onPayNow: () => _showCheckoutDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showCheckoutDialog(BuildContext context) {
    final cart = context.read<CartProvider>();

    showDialog(
      context: context,
      builder: (dialogContext) => _PaymentDialog(
        cart: cart,
        onComplete: (amountPaid, sellerId, existingDueTotal, description) async {
          Navigator.pop(dialogContext);
          await _processSale(context, amountPaid, sellerId, existingDueTotal, description);
        },
      ),
    );
  }

  Future<void> _processSale(BuildContext context, double amountPaid, String? sellerId, double existingDueTotal, String? description) async {
    final cart = context.read<CartProvider>();
    final productService = ProductService();
    final salesService = SalesService();

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Update stock for each product
      // Use batch write for better performance and atomicity
      final batch = FirebaseFirestore.instance.batch();
      for (var cartItem in cart.items.values) {
        final docRef = FirebaseFirestore.instance
            .collection('products')
            .doc(cartItem.product.id);
        final doc = await docRef.get();
        
        if (doc.exists) {
          final product = Product.fromMap(doc.data()!);
          if (product.stock >= cartItem.quantity) {
            final updatedProduct = product.copyWith(
              stock: product.stock - cartItem.quantity,
              updatedAt: DateTime.now(),
            );
            batch.update(docRef, updatedProduct.toMap());
          }
        }
      }
      // Commit all stock updates at once
      await batch.commit();

      // Calculate total profit based on actual selling price (could be regular or wholesale)
      double totalProfit = 0;
      for (var cartItem in cart.items.values) {
        final profitPerItem = cartItem.unitPrice - cartItem.product.purchasePrice;
        totalProfit += profitPerItem * cartItem.quantity;
      }

      // Initialize variables for seller processing
      // Note: Credit balance usage and recovery balance calculation happen during seller processing
      double recoveryBalance = 0.0;
      double change = 0.0;
      
      // For now, calculate change based on cash payment only
      // Recovery balance will be calculated during seller processing if seller exists
      if (amountPaid > cart.totalAmount) {
        // Excess cash payment - change calculation depends on seller and dues
        // We'll refine this during seller processing, but for non-seller cases:
        if (sellerId == null) {
          change = amountPaid - cart.totalAmount;
        }
        // For seller cases, change/recovery will be calculated after credit is applied
      }

      // Create sale (recoveryBalance and creditUsed will be updated after seller processing if needed)
      // amountPaid should only include cash (credit is handled separately in seller processing)
      Sale sale = Sale(
        id: const Uuid().v4(),
        items: cart.items.values
            .map((cartItem) => SaleItem(
                  productId: cartItem.product.id,
                  productName: cartItem.product.name,
                  price: cartItem.unitPrice,
                  quantity: cartItem.quantity,
                  subtotal: cartItem.subtotal,
                ))
            .toList(),
        total: cart.totalAmount,
        profit: totalProfit,
        amountPaid: amountPaid, // Only cash, credit is handled separately
        change: change,
        createdAt: DateTime.now(),
        sellerId: sellerId,
        recoveryBalance: recoveryBalance, // Will be set during seller processing
        creditUsed: 0.0, // Will be set during seller processing
        saleType: cart.saleType == SaleType.wholesale ? 'wholesale' : 'regular',
        description: description,
      );

      await salesService.addSale(sale);

      // Save seller history and due payment if seller is selected
      if (sellerId != null) {
        debugPrint('=== PROCESSING SELLER PAYMENT ===');
        debugPrint('Seller ID: $sellerId');
        debugPrint('Amount Paid (Cash): $amountPaid');
        debugPrint('Cart Total: ${cart.totalAmount}');
        debugPrint('Existing Due Total: $existingDueTotal');
        
        final sellerService = SellerService();
        
        // Check for credit balance first
        double creditBalance = await sellerService.getCreditBalance(sellerId);
        debugPrint('Credit Balance: $creditBalance');
        
        // Calculate how payment is applied:
        // 1. Use credit balance first (if available) to pay current sale
        // 2. Then use cash payment to pay current sale
        // 3. Remaining cash goes to existing dues
        
        double creditUsed = 0.0;
        double remainingSaleAmount = cart.totalAmount;
        
        // Use credit balance first
        if (creditBalance > 0 && remainingSaleAmount > 0) {
          creditUsed = await sellerService.useCreditBalance(sellerId, remainingSaleAmount);
          remainingSaleAmount -= creditUsed;
          debugPrint('Credit Used: $creditUsed');
          debugPrint('Remaining Sale Amount after credit: $remainingSaleAmount');
        }
        
        // Now calculate cash payment allocation
        double cashForCurrentSale = remainingSaleAmount > 0 && amountPaid > 0
            ? (amountPaid < remainingSaleAmount ? amountPaid : remainingSaleAmount)
            : 0.0;
        double cashForExistingDues = amountPaid > cashForCurrentSale
            ? amountPaid - cashForCurrentSale
            : 0.0;
        
        // Total amount paid for current sale (credit + cash)
        double totalAmountForCurrentSale = creditUsed + cashForCurrentSale;
        
        debugPrint('Cash for current sale: $cashForCurrentSale');
        debugPrint('Cash for existing dues: $cashForExistingDues');
        debugPrint('Total amount for current sale (credit + cash): $totalAmountForCurrentSale');
        
        // Update recovery balance and change based on actual cash allocation
        double actualRecoveryBalance = 0.0;
        double actualChange = 0.0;
        
        // Apply cash payment to existing due payments (if any)
        if (cashForExistingDues > 0 && existingDueTotal > 0) {
          debugPrint('Applying $cashForExistingDues to existing due payments...');
          try {
            final remainingAfterDues = await sellerService.applyPaymentToDuePayments(sellerId, cashForExistingDues);
            actualRecoveryBalance = cashForExistingDues - remainingAfterDues;
            // If there's remaining after paying dues, it should be returned as change (not added to credit)
            // Change is money returned to the customer, not credit for the seller
            if (remainingAfterDues > 0) {
              actualChange = remainingAfterDues;
              debugPrint('Remaining payment after dues returned as change: $remainingAfterDues');
            }
            debugPrint('✓ Payment applied to existing due payments. Recovery Balance: $actualRecoveryBalance');
          } catch (e) {
            debugPrint('✗ Error applying payment to existing dues: $e');
          }
        } else {
          // Calculate change if there's excess cash
          // IMPORTANT: Change should be returned to customer, NOT added to seller's credit balance
          // Change is money the customer overpaid and should be returned
          // Change = cash paid - cash needed for current sale (credit is NOT part of cash payment)
          // Example: Sale = 5000, Credit = 3750, Cash needed = 1250, Customer pays 1500
          //   Change = 1500 - 1250 = 250 ✓ (NOT 1500 - 5000 = -3500 ✗)
          if (amountPaid > cashForCurrentSale) {
            actualChange = amountPaid - cashForCurrentSale;
            debugPrint('Excess cash payment returned as change: $actualChange');
            debugPrint('  - Cash paid: $amountPaid');
            debugPrint('  - Cash needed for sale (after credit): $cashForCurrentSale');
            debugPrint('  - Change: $actualChange');
          }
        }
        
        // Update sale with correct recoveryBalance and creditUsed (only if they changed)
        if (actualRecoveryBalance > 0 || actualChange != change || creditUsed > 0) {
          await FirebaseFirestore.instance.collection('sales').doc(sale.id).update({
            'recoveryBalance': actualRecoveryBalance,
            'change': actualChange,
            'creditUsed': creditUsed,
          });
          // Create updated sale object for receipt display
          sale = Sale(
            id: sale.id,
            items: sale.items,
            total: sale.total,
            profit: sale.profit,
            amountPaid: sale.amountPaid,
            change: actualChange,
            createdAt: sale.createdAt,
            customerName: sale.customerName,
            paymentMethod: sale.paymentMethod,
            returnedAmount: sale.returnedAmount,
            isPartialReturn: sale.isPartialReturn,
            sellerId: sale.sellerId,
            recoveryBalance: actualRecoveryBalance,
            isBorrowPayment: sale.isBorrowPayment,
            creditUsed: creditUsed,
            saleType: sale.saleType,
            description: sale.description,
          );
        }
        
        // Save seller history for current sale (with total payment including credit)
        try {
          await sellerService.addSellerHistory(
            sellerId: sellerId,
            saleId: sale.id,
            saleAmount: sale.total,
            amountPaid: totalAmountForCurrentSale,
            saleDate: sale.createdAt,
          );
          debugPrint('✓ Seller history saved for seller: $sellerId');
          debugPrint('  - Sale Amount: ${sale.total}');
          debugPrint('  - Amount Paid (credit + cash): $totalAmountForCurrentSale');
          debugPrint('  - Due Payment: ${sale.total > totalAmountForCurrentSale ? sale.total - totalAmountForCurrentSale : 0.0}');
        } catch (e) {
          debugPrint('✗ Error saving seller history: $e');
        }
        
        // Check if current sale has remaining due (after credit and cash payment applied)
        if (totalAmountForCurrentSale < cart.totalAmount) {
          final dueAmount = cart.totalAmount - totalAmountForCurrentSale;
          debugPrint('Partial payment for current sale. Due amount: $dueAmount');
          
          try {
            final duePayment = DuePayment(
              id: const Uuid().v4(),
              sellerId: sellerId,
              saleId: sale.id,
              totalAmount: cart.totalAmount,
              amountPaid: totalAmountForCurrentSale,
              dueAmount: dueAmount,
              createdAt: DateTime.now(),
              isPaid: false,
            );
            
            debugPrint('Creating due payment with ID: ${duePayment.id}');
            debugPrint('Due payment data: ${duePayment.toMap()}');
            
            await sellerService.addDuePayment(duePayment);
            debugPrint('✓ Due payment saved successfully: Rs. $dueAmount for seller: $sellerId');
          } catch (e) {
            debugPrint('✗ ERROR saving due payment: $e');
            debugPrint('Error stack trace: ${StackTrace.current}');
          }
        } else {
          debugPrint('Current sale fully paid.');
        }
        
        debugPrint('=== END SELLER PAYMENT PROCESSING ===');
      } else {
        debugPrint('No seller selected. Skipping seller history and due payment.');
      }

      // Clear cart
      cart.clear();

      if (context.mounted) {
        Navigator.pop(context); // Close loading
        _showReceiptDialog(context, sale, existingDueTotal);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showReceiptDialog(BuildContext context, Sale sale, double existingDueTotal) async {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final dateFormatter = DateFormat('MMM dd, yyyy - hh:mm a');
    
    // Load current language preference
    final printerService = PrinterService();
    String selectedLanguage = await printerService.getReceiptLanguage();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            Container(
              width: 400,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success Icon
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 64,
                    ),
                  ),
              const SizedBox(height: 20),
              const Text(
                'Payment Successful!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Transaction completed successfully',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    _ReceiptRow(
                      label: 'Sale Amount',
                      value: formatter.format(sale.total),
                      isTotal: false,
                    ),
                    if (sale.creditUsed > 0) ...[
                      const Divider(height: 24),
                      _ReceiptRow(
                        label: 'Credit Applied',
                        value: formatter.format(sale.creditUsed),
                        isTotal: false,
                        color: Colors.blue,
                      ),
                    ],
                    const Divider(height: 24),
                    _ReceiptRow(
                      label: 'Amount Paid',
                      value: formatter.format(sale.amountPaid),
                      isTotal: false,
                    ),
                    const Divider(height: 24),
                    _ReceiptRow(
                      label: 'Change',
                      value: formatter.format(sale.change),
                      isTotal: true,
                      color: sale.change > 0 ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Transaction ID',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Text(
                                sale.id.substring(0, 8).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateFormatter.format(sale.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        debugPrint('Print button clicked');
                        try {
                          // Check if printer is configured
                          final printerService = PrinterService();
                          final connectionType = await printerService.getConnectionType();
                          
                          bool needsConfiguration = false;
                          if (connectionType == PrinterConnectionType.wifi) {
                            final printerIp = await printerService.getPrinterIp();
                            needsConfiguration = printerIp == null || printerIp.isEmpty;
                          } else if (connectionType == PrinterConnectionType.bluetooth) {
                            final btDeviceId = await printerService.getBluetoothDeviceId();
                            needsConfiguration = btDeviceId == null;
                          } else if (connectionType == PrinterConnectionType.usb) {
                            final usbDeviceId = await printerService.getUsbDeviceId();
                            needsConfiguration = usbDeviceId == null;
                          }
                          
                          if (needsConfiguration) {
                            // Show configuration dialog
                            if (context.mounted) {
                              await _showPrinterConfigDialog(context, printerService);
                            }
                            return;
                          }

                          // Fetch seller information if sellerId exists
                          Seller? seller;
                          if (sale.sellerId != null) {
                            debugPrint('Fetching seller with ID: ${sale.sellerId}');
                            final sellerService = SellerService();
                            seller = await sellerService.getSellerById(sale.sellerId!);
                            debugPrint('Seller fetched: ${seller?.name ?? 'null'}');
                          }

                          // Get current language preference
                          final currentLanguage = await printerService.getReceiptLanguage();
                          
                          // Print directly to thermal printer
                          final success = await printerService.printReceipt(sale, existingDueTotal, seller, languageCode: currentLanguage);
                          
                          if (success && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Receipt printed successfully'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } else if (context.mounted) {
                            // Get connection type to show appropriate error
                            final currentConnectionType = await printerService.getConnectionType();
                            String errorMessage = 'Failed to print receipt. Please check printer connection.';
                            
                            if (currentConnectionType == PrinterConnectionType.bluetooth) {
                              errorMessage = 'Bluetooth printing failed. Your printer may use classic Bluetooth (SPP) which is not supported by web browsers. Please use WiFi connection instead, or use a BLE-compatible printer.';
                            }
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 8),
                                action: SnackBarAction(
                                  label: 'Use WiFi',
                                  textColor: Colors.white,
                                  onPressed: () {
                                    // Open printer config dialog
                                    final service = PrinterService();
                                    _showPrinterConfigDialog(context, service);
                                  },
                                ),
                              ),
                            );
                          }
                        } catch (e, stackTrace) {
                          debugPrint('Error printing receipt: $e');
                          debugPrint('Stack trace: $stackTrace');
                          if (context.mounted) {
                            final errorMsg = e.toString();
                            String userMessage = 'Print error: $e';
                            
                            // Check if it's the unsupported device error
                            if (errorMsg.contains('Unsupported device') || 
                                errorMsg.contains('classic Bluetooth') ||
                                errorMsg.contains('SPP') ||
                                errorMsg.contains('No Services found')) {
                              userMessage = 'Your printer uses classic Bluetooth (SPP) which is not supported by Web Bluetooth API. Web browsers only support Bluetooth Low Energy (BLE) devices. Please use WiFi connection instead.';
                            }
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(userMessage),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 8),
                                action: SnackBarAction(
                                  label: 'Use WiFi',
                                  textColor: Colors.white,
                                  onPressed: () {
                                    // Open printer config dialog
                                    final service = PrinterService();
                                    _showPrinterConfigDialog(context, service);
                                  },
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Print'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // WhatsApp Icon Button
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () async {
                        await _shareViaWhatsApp(context, sale, existingDueTotal);
                      },
                      icon: const Icon(
                        Icons.chat_bubble,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: 'Share via WhatsApp',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.done),
                      label: const Text('Done'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
            // Refresh Icon Button at Top Left (Reset Print Settings)
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () async {
                  // Show confirmation dialog
                  final shouldReset = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.refresh, color: Colors.orange),
                          SizedBox(width: 12),
                          Text('Reset Print Settings'),
                        ],
                      ),
                      content: const Text(
                        'Are you sure you want to reset all printer settings? This will clear the printer IP, port, connection type, and device information.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );

                  if (shouldReset == true) {
                    try {
                      final printerService = PrinterService();
                      await printerService.resetPrinterSettings();
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Print settings have been reset successfully'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error resetting print settings: $e'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.orange,
                ),
                tooltip: 'Reset Print Settings',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
            // Language Selector Icon Button (between refresh and eye)
            Positioned(
              top: 8,
              right: 56,
              child: PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.language,
                    color: Colors.blue,
                  ),
                ),
                tooltip: 'Select Receipt Language',
                onSelected: (String language) async {
                  setDialogState(() {
                    selectedLanguage = language;
                  });
                  await printerService.setReceiptLanguage(language);
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('Receipt language set to: ${_getLanguageName(language)}'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'en',
                    child: Row(
                      children: [
                        Icon(
                          Icons.check,
                          size: 16,
                          color: selectedLanguage == 'en' ? Colors.green : Colors.transparent,
                        ),
                        const SizedBox(width: 8),
                        const Text('English'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'ur',
                    child: Row(
                      children: [
                        Icon(
                          Icons.check,
                          size: 16,
                          color: selectedLanguage == 'ur' ? Colors.green : Colors.transparent,
                        ),
                        const SizedBox(width: 8),
                        const Text('Urdu'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'ar',
                    child: Row(
                      children: [
                        Icon(
                          Icons.check,
                          size: 16,
                          color: selectedLanguage == 'ar' ? Colors.green : Colors.transparent,
                        ),
                        const SizedBox(width: 8),
                        const Text('Arabic'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Eye Icon Button at Top Right
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () {
                  Navigator.pop(context); // Close the success dialog first
                  _showPrintPreview(context, sale, existingDueTotal, languageCode: selectedLanguage);
                },
                icon: const Icon(
                  Icons.visibility,
                  color: Colors.grey,
                ),
                tooltip: 'Preview Receipt',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
          ],
        ),
      ),
        ),
    );
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'ur':
        return 'Urdu';
      case 'ar':
        return 'Arabic';
      default:
        return 'English';
    }
  }

  Future<void> _showPrintPreview(BuildContext context, Sale sale, double existingDueTotal, {String? languageCode}) async {
    try {
      debugPrint('=== Starting Print Preview ===');
      
      // Fetch seller information if sellerId exists
      Seller? seller;
      if (sale.sellerId != null) {
        debugPrint('Fetching seller with ID: ${sale.sellerId}');
        final sellerService = SellerService();
        seller = await sellerService.getSellerById(sale.sellerId!);
        debugPrint('Seller fetched: ${seller?.name ?? 'null'}');
      }

      debugPrint('Showing print preview dialog...');
      
      // Show print preview dialog - use root navigator to show above other dialogs
      if (!context.mounted) {
        debugPrint('Context not mounted, cannot show dialog');
        return;
      }
      
      debugPrint('About to show dialog...');
      await showDialog(
        useRootNavigator: true,
        barrierDismissible: true,
        context: context,
        builder: (dialogContext) {
          debugPrint('Dialog builder called');
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: 600,
              height: 700,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Print Preview',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: PdfPreview(
                      build: (format) async {
                        try {
                          final lang = languageCode ?? await PrinterService().getReceiptLanguage();
                          return await _generateReceiptPDF(sale, existingDueTotal, seller, languageCode: lang);
                        } catch (e) {
                          debugPrint('PDF Generation Error: $e');
                          rethrow;
                        }
                      },
                      allowPrinting: true,
                      allowSharing: true,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final lang = languageCode ?? await PrinterService().getReceiptLanguage();
                            final pdf = await _generateReceiptPDF(sale, existingDueTotal, seller, languageCode: lang);
                            await Printing.layoutPdf(
                              onLayout: (format) async => pdf,
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Print error: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.print),
                        label: const Text('Print'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error showing preview: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareViaWhatsApp(BuildContext context, Sale sale, double existingDueTotal) async {
    try {
      // Show loading indicator
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Fetch seller information if sellerId exists
      Seller? seller;
      if (sale.sellerId != null) {
        final sellerService = SellerService();
        seller = await sellerService.getSellerById(sale.sellerId!);
      }

      // Get current language preference
      final printerService = PrinterService();
      final currentLanguage = await printerService.getReceiptLanguage();
      
      // Generate PDF
      final pdfBytes = await _generateReceiptPDF(sale, existingDueTotal, seller, languageCode: currentLanguage);

      // Get seller phone number
      String? phoneNumber = seller?.phone;
      
      // Clean phone number (remove spaces, dashes, etc.)
      if (phoneNumber != null) {
        phoneNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
        // Remove country code if present and add if needed
        if (phoneNumber.startsWith('+')) {
          // Keep as is
        } else if (phoneNumber.startsWith('0')) {
          // Remove leading 0 and add country code (assuming Pakistan +92)
          phoneNumber = '+92${phoneNumber.substring(1)}';
        } else {
          // Add country code (assuming Pakistan +92)
          phoneNumber = '+92$phoneNumber';
        }
      }

      if (kIsWeb) {
        // Web: Use WhatsApp Web API
        if (phoneNumber != null && phoneNumber.isNotEmpty) {
          // For web, download the PDF first, then open WhatsApp Web
          // Download PDF using share_plus (works on web)
          try {
            final xFile = XFile.fromData(
              pdfBytes,
              mimeType: 'application/pdf',
              name: 'receipt_${sale.id.substring(0, 8)}.pdf',
            );
            
            // Share the file (will download on web)
            await Share.shareXFiles([xFile], text: 'Receipt for Sale #${sale.id.substring(0, 8).toUpperCase()}');
            
            // Open WhatsApp Web with phone number
            final whatsappUrl = Uri.parse('https://wa.me/$phoneNumber');
            if (await canLaunchUrl(whatsappUrl)) {
              await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
              
              if (context.mounted) {
                Navigator.pop(context); // Close loading
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PDF downloaded. WhatsApp opened. Please attach the downloaded PDF file.'),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            } else {
              if (context.mounted) {
                Navigator.pop(context); // Close loading
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PDF downloaded. Could not open WhatsApp. Please open WhatsApp Web manually.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Error sharing PDF on web: $e');
            // Fallback: just open WhatsApp
            final whatsappUrl = Uri.parse('https://wa.me/$phoneNumber');
            if (await canLaunchUrl(whatsappUrl)) {
              await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
            }
            if (context.mounted) {
              Navigator.pop(context); // Close loading
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('WhatsApp opened. Please manually attach the receipt PDF. Error: $e'),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        } else {
          if (context.mounted) {
            Navigator.pop(context); // Close loading
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Seller phone number not found. Cannot share via WhatsApp.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        // Mobile (Android/iOS): Save PDF to temp file and share
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/receipt_${sale.id.substring(0, 8)}.pdf');
        await file.writeAsBytes(pdfBytes);

        // Share the file
        final result = await Share.shareXFiles(
          [XFile(file.path)],
          text: phoneNumber != null && phoneNumber.isNotEmpty
              ? 'Receipt for Sale #${sale.id.substring(0, 8).toUpperCase()}'
              : 'Receipt for Sale #${sale.id.substring(0, 8).toUpperCase()}',
          subject: 'Receipt',
        );

        if (context.mounted) {
          Navigator.pop(context); // Close loading
          
          if (result.status == ShareResultStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Receipt shared successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }

        // Clean up: delete temp file after a delay
        Future.delayed(const Duration(seconds: 5), () {
          try {
            if (file.existsSync()) {
              file.deleteSync();
            }
          } catch (e) {
            debugPrint('Error deleting temp file: $e');
          }
        });
      }
    } catch (e) {
      debugPrint('Error sharing via WhatsApp: $e');
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing via WhatsApp: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<Uint8List> _generateReceiptPDF(Sale sale, double existingDueTotal, Seller? seller, {String languageCode = 'en'}) async {
    try {
      final pdf = pw.Document();
      final formatter = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);
      final dateFormatter = DateFormat('MMM dd, yyyy - hh:mm a');
      
      // Fetch products to get language-specific names
      final productService = ProductService();
      final Map<String, String> productNamesMap = {};
      
      // Fetch all products for this sale
      for (var item in sale.items) {
        try {
          final product = await productService.getProductById(item.productId);
          if (product != null) {
            // Get name in selected language, fallback to English or displayName
            final name = product.getName(languageCode) ?? 
                        (languageCode == 'en' ? product.name : product.getName('en')) ?? 
                        product.name;
            productNamesMap[item.productId] = name;
          } else {
            // Fallback to stored productName if product not found
            productNamesMap[item.productId] = item.productName;
          }
        } catch (e) {
          debugPrint('Error fetching product ${item.productId}: $e');
          // Fallback to stored productName
          productNamesMap[item.productId] = item.productName;
        }
      }

      // Use monospace Courier font for receipt (standard receipt printer style)
      final font = pw.Font.courier();
      
      // Helper function to create text style with standard font
      pw.TextStyle textStyle({
        double fontSize = 6,
        pw.FontWeight? fontWeight,
      }) {
        return pw.TextStyle(
          font: font,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      }
      
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 3 * PdfPageFormat.mm),
          build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header: AR'S Traders
              pw.Text(
                'AR\'S Traders',
                style: textStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              
              // Seller Information - More Prominent
              if (seller != null) ...[
                pw.SizedBox(height: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'CUSTOMER NAME:',
                        style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        seller.name.toUpperCase(),
                        style: textStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                      if (seller.phone != null && seller.phone!.isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Phone: ${seller.phone!}',
                          style: textStyle(fontSize: 6),
                        ),
                      ],
                      if (seller.location != null && seller.location!.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Address: ${seller.location!}',
                          style: textStyle(fontSize: 6),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(height: 4),
              ],
              
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 3),
              
              // Items Table Header - simplified like receipt format
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(
                      'No.',
                      style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.left,
                    ),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                      'Item',
                      style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.left,
                    ),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(
                      'Qty',
                      style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'Price',
                      style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'Amount',
                      style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 2),
              
              // Items List with numbering
              ...sale.items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final itemNumber = (index + 1).toString().padLeft(2, '0');
                
                return pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 1,
                          child: pw.Text(
                            itemNumber,
                            style: textStyle(fontSize: 6),
                            textAlign: pw.TextAlign.left,
                          ),
                        ),
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(
                            productNamesMap[item.productId] ?? item.productName,
                            style: textStyle(fontSize: 6),
                            maxLines: 2,
                            textAlign: pw.TextAlign.left,
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Text(
                            item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2),
                            style: textStyle(fontSize: 6),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            formatter.format(item.price),
                            style: textStyle(fontSize: 6),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            formatter.format(item.subtotal),
                            style: textStyle(fontSize: 6),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                  ],
                );
              }).toList(),
              
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 3),
              
              // Total Quantity Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total Items: ${sale.items.length}',
                    style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'Total Qty: ${sale.items.fold<double>(0, (sum, item) => sum + item.quantity).toStringAsFixed(sale.items.any((item) => item.quantity % 1 != 0) ? 2 : 0)}',
                    style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 3),
              
              // Payment Summary
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Sale Amount:',
                    style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    formatter.format(sale.total),
                    style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              if (sale.creditUsed > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Credit Applied:',
                      style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      formatter.format(sale.creditUsed),
                      style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Amount Paid:',
                    style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    formatter.format(sale.amountPaid),
                    style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Change:',
                    style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    formatter.format(sale.change),
                    style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 3),
              
              // Order ID
              pw.Text(
                'Order ID: ${sale.id.substring(0, 8).toUpperCase()}',
                style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                dateFormatter.format(sale.createdAt),
                style: textStyle(fontSize: 6),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              
              // Footer
              pw.Text(
                'Thank you come again',
                      style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              // Contact Information
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        '03017826712',
                        style: textStyle(fontSize: 6),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'M.Irfan',
                        style: textStyle(fontSize: 6),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        '03015384952',
                        style: textStyle(fontSize: 6),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'M.Usman',
                        style: textStyle(fontSize: 6),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              // Software Developer Information
              pw.Text(
                'Software Developed by:',
                style: textStyle(fontSize: 6),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'HighApp Solution 0301-5384952',
                style: textStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

      final pdfBytes = await pdf.save();
      debugPrint('PDF generated successfully, size: ${pdfBytes.length} bytes');
      return pdfBytes;
    } catch (e, stackTrace) {
      debugPrint('Error generating PDF: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _showPrinterConfigDialog(BuildContext context, PrinterService printerService) async {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '9100');
    
    // Load existing settings
    final existingIp = await printerService.getPrinterIp();
    final existingPort = await printerService.getPrinterPort();
    final existingConnectionType = await printerService.getConnectionType();
    final existingBtDeviceName = await printerService.getBluetoothDeviceName();
    
    if (existingIp != null) {
      ipController.text = existingIp;
    }
    portController.text = existingPort;

    PrinterConnectionType selectedConnectionType = existingConnectionType;
    String? selectedBtDeviceName = existingBtDeviceName;
    String? selectedUsbDeviceName = await printerService.getUsbDeviceName();
    bool isBluetoothAvailable = printerService.isBluetoothAvailable();
    bool isUsbAvailable = printerService.isUsbAvailable();

    return showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.print, color: Colors.green),
              SizedBox(width: 8),
              Text('Printer Configuration'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configure your SpeedX SP-90A thermal printer',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                
                // Connection Type Selector
                const Text(
                  'Connection Type *',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<PrinterConnectionType>(
                        title: const Text('WiFi'),
                        value: PrinterConnectionType.wifi,
                        groupValue: selectedConnectionType,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedConnectionType = value!;
                          });
                        },
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<PrinterConnectionType>(
                        title: const Text('Bluetooth'),
                        value: PrinterConnectionType.bluetooth,
                        groupValue: selectedConnectionType,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedConnectionType = value!;
                          });
                        },
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<PrinterConnectionType>(
                        title: const Text('USB'),
                        value: PrinterConnectionType.usb,
                        groupValue: selectedConnectionType,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedConnectionType = value!;
                          });
                        },
                        dense: true,
                      ),
                    ),
                  ],
                ),
                
                if (!isBluetoothAvailable && selectedConnectionType == PrinterConnectionType.bluetooth)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Bluetooth is only available on web (Chrome/Edge). Use WiFi for mobile/desktop.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ),
                
                if (!isUsbAvailable && selectedConnectionType == PrinterConnectionType.usb)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'USB is only available on web (Chrome/Edge). Use WiFi for mobile/desktop.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // WiFi Configuration
                if (selectedConnectionType == PrinterConnectionType.wifi) ...[
                  TextField(
                    controller: ipController,
                    decoration: const InputDecoration(
                      labelText: 'Printer IP Address *',
                      hintText: '192.168.1.23',
                      prefixIcon: Icon(Icons.dns),
                      border: OutlineInputBorder(),
                      helperText: 'Enter the IP address of your thermal printer',
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: 'Printer Port',
                      hintText: '9100',
                      prefixIcon: Icon(Icons.settings_ethernet),
                      border: OutlineInputBorder(),
                      helperText: 'Default port for network thermal printers is 9100',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                
                // Bluetooth Configuration
                if (selectedConnectionType == PrinterConnectionType.bluetooth && isBluetoothAvailable) ...[
                  // Important note about Web Bluetooth
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Important:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Web Bluetooth API only supports Bluetooth Low Energy (BLE) devices.\nIf your printer uses classic Bluetooth (SPP), it will not work.\nIn that case, please use WiFi connection instead.\n\nJust ensure your printer is powered ON and Bluetooth is enabled.',
                          style: TextStyle(fontSize: 11, color: Colors.blue[800]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (selectedBtDeviceName != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth_connected, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected Device:',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                Text(
                                  selectedBtDeviceName ?? 'Unknown',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[900]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        // Show loading indicator
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Searching for Bluetooth devices...'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                        
                        final device = await printerService.requestBluetoothDevice();
                        if (device != null && context.mounted) {
                          final deviceName = device['name'] as String?;
                          final deviceId = device['id'] as String?;
                          
                          debugPrint('Device selection result: name=$deviceName, id=$deviceId');
                          
                          if (deviceName != null) {
                            // Update the dialog state
                            setDialogState(() {
                              selectedBtDeviceName = deviceName;
                            });
                            
                            // Verify the device was saved
                            final savedId = await printerService.getBluetoothDeviceId();
                            final savedName = await printerService.getBluetoothDeviceName();
                            debugPrint('Device saved check: id=$savedId, name=$savedName');
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Bluetooth device selected: $deviceName'),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          } else {
                            debugPrint('Device name is null');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Device selected but name is missing'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        } else if (context.mounted) {
                          debugPrint('No device returned from requestBluetoothDevice');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No device selected or selection cancelled'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('Error selecting Bluetooth device: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.bluetooth_searching),
                    label: Text(selectedBtDeviceName != null ? 'Change Device' : 'Select Bluetooth Device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Printer Details:\n• Name: "BlueTooth Printer"\n• PIN: 1234 (entered automatically by browser)\n• Make sure printer is ON and Bluetooth enabled',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                
                // USB Configuration
                if (selectedConnectionType == PrinterConnectionType.usb && isUsbAvailable) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Important:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Web USB API requires Chrome, Edge, or Opera browser.\nMake sure your printer is connected via USB cable.\nThe browser will prompt you to select the device.',
                          style: TextStyle(fontSize: 11, color: Colors.blue[800]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (selectedUsbDeviceName != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.usb, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected Device:',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                Text(
                                  selectedUsbDeviceName ?? 'Unknown',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[900]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Requesting USB device access...'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                        
                        final device = await printerService.requestUsbDevice();
                        if (device != null && context.mounted) {
                          final deviceName = device['name'] as String?;
                          
                          if (deviceName != null) {
                            setDialogState(() {
                              selectedUsbDeviceName = deviceName;
                            });
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('USB device selected: $deviceName'),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.usb),
                    label: Text(selectedUsbDeviceName != null ? 'Change Device' : 'Select USB Device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure:\n• Printer is connected via USB cable\n• Printer is powered ON\n• Use Chrome, Edge, or Opera browser',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: () async {
              if (selectedConnectionType == PrinterConnectionType.wifi) {
                final ip = ipController.text.trim();
                final port = portController.text.trim();
                
                if (ip.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter printer IP address'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Temporarily set IP and port for testing
                final originalIp = await printerService.getPrinterIp();
                final originalPort = await printerService.getPrinterPort();
                final originalType = await printerService.getConnectionType();
                
                try {
                  await printerService.setPrinterIp(ip);
                  await printerService.setPrinterPort(port.isEmpty ? '9100' : port);
                  await printerService.setConnectionType(PrinterConnectionType.wifi);
                  
                  // Show loading
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Testing connection...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                  
                  // Test connection
                  final success = await printerService.testConnection();
                  
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success 
                            ? 'Connection test successful! Printer is reachable.' 
                            : 'Connection test failed. Please check IP address and ensure printer is on the same network.'),
                        backgroundColor: success ? Colors.green : Colors.orange,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                  
                  // Restore original settings if test failed
                  if (!success) {
                    if (originalIp != null) {
                      await printerService.setPrinterIp(originalIp);
                    }
                    await printerService.setPrinterPort(originalPort);
                    await printerService.setConnectionType(originalType);
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error testing connection: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  // Restore original settings
                  if (originalIp != null) {
                    await printerService.setPrinterIp(originalIp);
                  }
                  await printerService.setPrinterPort(originalPort);
                  await printerService.setConnectionType(originalType);
                }
              } else if (selectedConnectionType == PrinterConnectionType.bluetooth) {
                // Bluetooth test
                if (selectedBtDeviceName == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a Bluetooth device first'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  await printerService.setConnectionType(PrinterConnectionType.bluetooth);
                  
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Testing Bluetooth connection...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                  
                  final success = await printerService.testConnection();
                  
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success 
                            ? 'Bluetooth connection test successful!' 
                            : 'Bluetooth connection test failed. Please ensure the printer is powered on and in range.'),
                        backgroundColor: success ? Colors.green : Colors.orange,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error testing Bluetooth connection: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else if (selectedConnectionType == PrinterConnectionType.usb) {
                // USB test
                if (selectedUsbDeviceName == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a USB device first'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  await printerService.setConnectionType(PrinterConnectionType.usb);
                  
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Testing USB connection...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                  
                  final success = await printerService.testConnection();
                  
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success 
                            ? 'USB connection test successful!' 
                            : 'USB connection test failed. Please ensure the printer is connected via USB and powered on.'),
                        backgroundColor: success ? Colors.green : Colors.orange,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error testing USB connection: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            icon: Icon(
              selectedConnectionType == PrinterConnectionType.wifi 
                  ? Icons.wifi_protected_setup 
                  : selectedConnectionType == PrinterConnectionType.bluetooth
                      ? Icons.bluetooth_searching
                      : Icons.usb,
              size: 18,
            ),
            label: const Text('Test'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue,
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedConnectionType == PrinterConnectionType.wifi) {
                final ip = ipController.text.trim();
                final port = portController.text.trim();
                
                if (ip.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter printer IP address'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  await printerService.setPrinterIp(ip);
                  await printerService.setPrinterPort(port.isEmpty ? '9100' : port);
                  await printerService.setConnectionType(PrinterConnectionType.wifi);
                  
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Printer configuration saved successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving configuration: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else if (selectedConnectionType == PrinterConnectionType.bluetooth) {
                // Bluetooth save
                // Check if device is already saved in preferences or selected in dialog
                final savedBtDeviceId = await printerService.getBluetoothDeviceId();
                final savedBtDeviceName = await printerService.getBluetoothDeviceName();
                
                // Use selected device name if available, otherwise use saved
                final deviceNameToUse = selectedBtDeviceName ?? savedBtDeviceName;
                
                // Check if we have either a device ID (which means device was selected) or a device name
                if (savedBtDeviceId == null && deviceNameToUse == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a Bluetooth device first. Click "Select Bluetooth Device" button.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 4),
                    ),
                  );
                  return;
                }

                try {
                  // Ensure connection type is set to Bluetooth
                  await printerService.setConnectionType(PrinterConnectionType.bluetooth);
                  
                  // If we have a selected device name but no saved device, the device was just selected
                  // The device should already be saved by requestBluetoothDevice, but let's verify
                  if (selectedBtDeviceName != null && savedBtDeviceId == null) {
                    // This shouldn't happen, but if it does, show a warning
                    debugPrint('Warning: Device name selected but device ID not saved');
                  }
                  
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Bluetooth printer configuration saved: ${deviceNameToUse ?? "Device"}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving configuration: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else if (selectedConnectionType == PrinterConnectionType.usb) {
                // USB save
                // Check if device is already saved in preferences or selected in dialog
                final savedUsbDeviceId = await printerService.getUsbDeviceId();
                final savedUsbDeviceName = await printerService.getUsbDeviceName();
                
                // Use selected device name if available, otherwise use saved
                final deviceNameToUse = selectedUsbDeviceName ?? savedUsbDeviceName;
                
                // Check if we have either a device ID (which means device was selected) or a device name
                if (savedUsbDeviceId == null && deviceNameToUse == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a USB device first. Click "Select USB Device" button.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 4),
                    ),
                  );
                  return;
                }

                try {
                  // Ensure connection type is set to USB
                  await printerService.setConnectionType(PrinterConnectionType.usb);
                  
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('USB printer configuration saved: ${deviceNameToUse ?? "Device"}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving configuration: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.onTap,
  });

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Dairy':
        return Icons.local_drink;
      case 'Vegetables':
        return Icons.eco;
      case 'Fruits':
        return Icons.apple;
      case 'Bakery':
        return Icons.bakery_dining;
      case 'Beverages':
        return Icons.coffee;
      case 'Snacks':
        return Icons.fastfood;
      case 'Personal Care':
        return Icons.face;
      case 'Household':
        return Icons.home;
      case 'Frozen':
        return Icons.ac_unit;
      default:
        return Icons.shopping_bag;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Dairy':
        return Colors.blue.shade100;
      case 'Vegetables':
        return Colors.green.shade100;
      case 'Fruits':
        return Colors.orange.shade100;
      case 'Bakery':
        return Colors.brown.shade100;
      case 'Beverages':
        return Colors.purple.shade100;
      case 'Snacks':
        return Colors.red.shade100;
      case 'Personal Care':
        return Colors.pink.shade100;
      case 'Household':
        return Colors.teal.shade100;
      case 'Frozen':
        return Colors.lightBlue.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');

    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        final isWholesale = cart.saleType == SaleType.wholesale;
        final hasWholesalePrice = product.wholesalePrice != null;
        final displayPrice = isWholesale && hasWholesalePrice 
            ? product.wholesalePrice! 
            : product.salePrice;
        final canAddToCart = !isWholesale || hasWholesalePrice;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
            onTap: canAddToCart ? onTap : null,
            child: Opacity(
              opacity: canAddToCart ? 1.0 : 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Product Image Area
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _getCategoryColor(product.category),
                      _getCategoryColor(product.category).withOpacity(0.6),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                          // Product image or icon fallback
                          if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                            Positioned.fill(
                              child: Image.network(
                                product.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  // Show icon if image fails to load
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          _getCategoryColor(product.category),
                                          _getCategoryColor(product.category).withOpacity(0.6),
                                        ],
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _getCategoryIcon(product.category),
                                        size: 56,
                                        color: Colors.black.withOpacity(0.3),
                                      ),
                                    ),
                                  );
                                },
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                              ),
                            )
                          else
                    Center(
                      child: Icon(
                        _getCategoryIcon(product.category),
                        size: 56,
                        color: Colors.black.withOpacity(0.3),
                      ),
                    ),
                    // Stock badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: product.stock <= 10
                              ? Colors.red
                              : Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          '${product.stock.toStringAsFixed(product.stock % 1 == 0 ? 0 : 1)} in stock',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                          // Wholesale indicator
                          if (hasWholesalePrice)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade600,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.business,
                                      color: Colors.white,
                                      size: 10,
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      'W',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Product Details
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Product name
                    Flexible(
                      flex: 2,
                      child: Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          height: 1.1,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Category badges
                    Flexible(
                      flex: 1,
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              product.category,
                              style: TextStyle(
                                fontSize: 7,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (product.formattedSize.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                product.formattedSize,
                                style: TextStyle(
                                  fontSize: 7,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Price and add button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isWholesale && hasWholesalePrice)
                                Text(
                                  'W',
                                  style: TextStyle(
                                    fontSize: 6,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (isWholesale && !hasWholesalePrice)
                                Text(
                                  'N/A',
                                  style: TextStyle(
                                    fontSize: 6,
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                formatter.format(displayPrice),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: canAddToCart ? Colors.green : Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: canAddToCart ? Colors.green : Colors.grey,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.add_shopping_cart,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
              ),
        ),
      ),
        );
      },
    );
  }
}

class _CartPanel extends StatelessWidget {
  final VoidCallback onPayNow;
  
  const _CartPanel({required this.onPayNow});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Cart Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade600, Colors.green.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shopping_cart, 
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Current Order',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Consumer<CartProvider>(
                builder: (context, cart, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${cart.totalItems}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        
        // Sale Type Selector
        Consumer<CartProvider>(
          builder: (context, cart, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sale Type',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<SaleType>(
                    segments: const [
                      ButtonSegment<SaleType>(
                        value: SaleType.regular,
                        label: Text('Regular Sale'),
                        icon: Icon(Icons.shopping_bag, size: 18),
                      ),
                      ButtonSegment<SaleType>(
                        value: SaleType.wholesale,
                        label: Text('Wholesale'),
                        icon: Icon(Icons.business, size: 18),
                      ),
                    ],
                    selected: {cart.saleType},
                    onSelectionChanged: (Set<SaleType> newSelection) {
                      cart.setSaleType(newSelection.first);
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<WidgetState> states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.green.shade600;
                          }
                          return Colors.grey.shade100;
                        },
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<WidgetState> states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return Colors.black87;
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        
        // Cart Items
        Expanded(
          child: Consumer<CartProvider>(
            builder: (context, cart, child) {
              if (cart.items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Cart is empty',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add products to start selling',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Reverse the list to show most recently added items first
              final cartItemsList = cart.items.values.toList().reversed.toList();
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: cartItemsList.length,
                itemBuilder: (context, index) {
                  final cartItem = cartItemsList[index];
                  return _CartItemTile(cartItem: cartItem);
                },
              );
            },
          ),
        ),
        
        _CartSummary(
          onPayNow: onPayNow,
        ),
      ],
    );
  }
}

class _CartItemTile extends StatefulWidget {
  final CartItem cartItem;

  const _CartItemTile({required this.cartItem});

  @override
  State<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<_CartItemTile> {
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  bool _isEditingQuantity = false;
  bool _isEditingPrice = false;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: widget.cartItem.quantity.toStringAsFixed(widget.cartItem.supportsFractionalQuantity ? 3 : 0));
    _priceController = TextEditingController(text: widget.cartItem.unitPrice.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.cartItem.product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isEditingPrice = true;
                          });
                          _priceController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _priceController.text.length,
                          );
                        },
                        child: _isEditingPrice
                            ? SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _priceController,
                                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                                  ],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.blue[600],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    isDense: true,
                                    hintText: '0.00',
                                  ),
                                  onSubmitted: (value) {
                                    _updatePrice(value);
                                  },
                                  onEditingComplete: () {
                                    _updatePrice(_priceController.text);
                                  },
                                  onTapOutside: (_) {
                                    _updatePrice(_priceController.text);
                                  },
                                ),
                              )
                            : Text(
                                '${formatter.format(widget.cartItem.unitPrice)} each',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                // Delete Button
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[400], size: 20),
                  onPressed: () {
                    context.read<CartProvider>().removeItem(widget.cartItem.product.id);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Quantity Controls
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () {
                          context
                              .read<CartProvider>()
                              .decreaseQuantity(widget.cartItem.product.id);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: const Icon(Icons.remove, size: 18),
                        ),
                      ),
                      // Quantity Input Field
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isEditingQuantity = true;
                          });
                          _quantityController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _quantityController.text.length,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          constraints: const BoxConstraints(minWidth: 40),
                          child: _isEditingQuantity
                              ? SizedBox(
                                  width: 50,
                                  child: TextField(
                                    controller: _quantityController,
                                    keyboardType: widget.cartItem.supportsFractionalQuantity 
                                        ? const TextInputType.numberWithOptions(decimal: true)
                                        : TextInputType.number,
                                    inputFormatters: widget.cartItem.supportsFractionalQuantity
                                        ? [
                                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                                          ]
                                        : [
                                            FilteringTextInputFormatter.digitsOnly,
                                          ],
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      isDense: true,
                                    ),
                                    onSubmitted: (value) {
                                      _updateQuantity(value);
                                    },
                                    onEditingComplete: () {
                                      _updateQuantity(_quantityController.text);
                                    },
                                    onTapOutside: (_) {
                                      _updateQuantity(_quantityController.text);
                                    },
                                  ),
                                )
                              : Text(
                                  widget.cartItem.quantity.toStringAsFixed(widget.cartItem.supportsFractionalQuantity ? 3 : 0),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          if (context
                              .read<CartProvider>()
                              .canAddMore(widget.cartItem.product.id)) {
                            context
                                .read<CartProvider>()
                                .increaseQuantity(widget.cartItem.product.id);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Maximum stock reached'),
                                duration: Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: const Icon(Icons.add, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                // Subtotal
                Text(
                  formatter.format(widget.cartItem.subtotal),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _updateQuantity(String value) {
    setState(() {
      _isEditingQuantity = false;
    });

    final quantity = double.tryParse(value);
    final minQuantity = widget.cartItem.supportsFractionalQuantity ? 0.1 : 1.0;
    
    if (quantity == null || quantity < minQuantity) {
      _quantityController.text = widget.cartItem.quantity.toStringAsFixed(widget.cartItem.supportsFractionalQuantity ? 3 : 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid quantity (minimum: ${minQuantity.toStringAsFixed(widget.cartItem.supportsFractionalQuantity ? 3 : 0)})'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (quantity > widget.cartItem.product.stock) {
      _quantityController.text = widget.cartItem.quantity.toStringAsFixed(widget.cartItem.supportsFractionalQuantity ? 3 : 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum stock available: ${widget.cartItem.product.stock}${widget.cartItem.product.unit}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (quantity < minQuantity) {
      context.read<CartProvider>().removeItem(widget.cartItem.product.id);
    } else {
      context.read<CartProvider>().updateQuantity(widget.cartItem.product.id, quantity);
    }
  }

  void _updatePrice(String value) {
    setState(() {
      _isEditingPrice = false;
    });

    final price = double.tryParse(value);
    if (price == null || price < 0) {
      _priceController.text = widget.cartItem.unitPrice.toStringAsFixed(2);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid price'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check if price is less than purchase price
    final purchasePrice = widget.cartItem.product.purchasePrice;
    final finalPrice = price < purchasePrice ? purchasePrice : price;

    // If price was adjusted, update the controller and show message
    if (price < purchasePrice) {
      _priceController.text = finalPrice.toStringAsFixed(2);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Price cannot be less than purchase price (Rs. ${purchasePrice.toStringAsFixed(2)}). Set to purchase price.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
        ),
      );
    }

    // Update the cart item with new price (only affects this cart session)
    context.read<CartProvider>().updatePrice(widget.cartItem.product.id, finalPrice);
    
    if (price >= purchasePrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Price updated to ${NumberFormat.currency(symbol: 'Rs. ').format(finalPrice)} (cart only)'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _CartSummary extends StatelessWidget {
  final VoidCallback onPayNow;
  
  const _CartSummary({required this.onPayNow});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Consumer<CartProvider>(
        builder: (context, cart, child) {
          return Column(
            children: [
              // Subtotal
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Subtotal (${cart.totalItems.toStringAsFixed(1)} items)',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatter.format(cart.totalAmount),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          formatter.format(cart.totalAmount),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: cart.items.isEmpty
                          ? null
                          : () {
                              cart.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cart cleared'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: cart.items.isEmpty
                          ? null
                          : onPayNow,
                      icon: const Icon(Icons.payment, size: 22),
                      label: const Text(
                        'Pay Now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  final CartProvider cart;
  final Function(double amountPaid, String? sellerId, double existingDueTotal, String? description) onComplete;

  const _PaymentDialog({
    required this.cart,
    required this.onComplete,
  });

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _sellerSearchController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final SellerService _sellerService = SellerService();
  final FocusNode _sellerFocusNode = FocusNode();
  Seller? _selectedSeller;
  bool _isDropdownOpen = false;
  List<Seller> _filteredSellers = [];
  StateSetter? _dialogStateSetter;
  List<DuePayment> _duePayments = [];
  bool _isLoadingDuePayments = false;

  @override
  void initState() {
    super.initState();
    _sellerSearchController.addListener(_filterSellers);
    _sellerFocusNode.addListener(() {
      // Only open dropdown on focus, don't close it (let selection close it)
      if (_sellerFocusNode.hasFocus && _sellerSearchController.text.isNotEmpty) {
        setState(() {
          _isDropdownOpen = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _sellerSearchController.dispose();
    _descriptionController.dispose();
    _sellerFocusNode.dispose();
    super.dispose();
  }

  void _filterSellers() {
    // Don't close dropdown when filtering - let user select
    if (!_isDropdownOpen && _sellerSearchController.text.isNotEmpty) {
      setState(() {
        _isDropdownOpen = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final quickAmounts = [500.0, 1000.0, 2000.0, 5000.0];

    debugPrint('=== BUILD PAYMENT DIALOG ===');
    debugPrint('_selectedSeller in build: ${_selectedSeller?.name ?? "null"}');
    debugPrint('_isDropdownOpen: $_isDropdownOpen');
    debugPrint('_filteredSellers count: ${_filteredSellers.length}');

    return StatefulBuilder(
      builder: (context, setDialogState) {
        // Store setDialogState so it can be accessed in nested widgets
        _dialogStateSetter = setDialogState;
        
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 450,
            constraints: const BoxConstraints(maxHeight: 700),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.payment, color: Colors.green.shade700, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Complete the transaction',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Current Sale Amount
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Current Sale Amount',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatter.format(widget.cart.totalAmount),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              // Due Payments Section (only show if seller is selected)
              if (_selectedSeller != null) ...[
                const SizedBox(height: 16),
                // Credit Balance Section
                FutureBuilder<double>(
                  future: _sellerService.getCreditBalance(_selectedSeller!.id),
                  builder: (context, creditSnapshot) {
                    final creditBalance = creditSnapshot.data ?? 0.0;
                    if (creditBalance > 0) {
                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.account_balance_wallet, color: Colors.blue.shade700, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Credit Balance',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                    if (creditSnapshot.connectionState == ConnectionState.waiting) ...[
                                      const SizedBox(width: 8),
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  formatter.format(creditBalance),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Credit will be automatically applied to this sale',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade800,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.pending_actions, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Due Payments',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade900,
                            ),
                          ),
                          if (_isLoadingDuePayments) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!_isLoadingDuePayments)
                        FutureBuilder<double>(
                          future: _selectedSeller != null
                              ? _sellerService.getCreditBalance(_selectedSeller!.id)
                              : Future.value(0.0),
                          builder: (context, creditSnapshot) {
                            // Get credit balance that will be automatically applied
                            final creditBalance = creditSnapshot.data ?? 0.0;
                            
                            // Calculate existing due total
                            final totalExistingDue = _duePayments.fold(0.0, (sum, p) => sum + p.dueAmount);
                            
                            // Only calculate remaining due if amount is actually entered
                            final hasAmountEntered = _amountController.text.isNotEmpty && 
                                double.tryParse(_amountController.text) != null;
                            final amountPaid = hasAmountEntered
                                ? double.tryParse(_amountController.text)!
                                : 0.0;
                            
                            // IMPORTANT: Credit balance is automatically applied to current sale
                            // So the effective sale amount after credit = saleAmount - creditBalance
                            final currentSaleAmount = widget.cart.totalAmount;
                            final saleAmountAfterCredit = (currentSaleAmount - creditBalance).clamp(0.0, currentSaleAmount);
                            
                            // Calculate how payment is applied:
                            // 1. Credit balance is applied first (automatically)
                            // 2. Then cash payment is applied to remaining sale amount
                            // 3. Remaining cash goes to existing dues
                            
                            // Amount available after paying current sale (after credit is applied)
                            final amountAfterCurrentSale = amountPaid > saleAmountAfterCredit
                                ? amountPaid - saleAmountAfterCredit
                                : 0.0;
                            
                            // Calculate remaining due after payment
                            final remainingExistingDue = amountAfterCurrentSale > 0
                                ? (totalExistingDue - amountAfterCurrentSale).clamp(0.0, totalExistingDue)
                                : totalExistingDue;
                            
                            // Calculate new due from current sale (if partial payment)
                            // This is the remaining amount after credit and cash payment
                            final newDueFromCurrentSale = amountPaid < saleAmountAfterCredit
                                ? saleAmountAfterCredit - amountPaid
                                : 0.0;
                            
                            // Total remaining due = remaining existing due + new due from current sale
                            final totalRemainingDue = remainingExistingDue + newDueFromCurrentSale;
                            
                            // Show only the sum
                            return Text(
                              formatter.format(totalRemainingDue),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
                // Subtotal (Current Sale + Existing Due Payments)
                FutureBuilder<double>(
                  future: _selectedSeller != null
                      ? _sellerService.getCreditBalance(_selectedSeller!.id)
                      : Future.value(0.0),
                  builder: (context, creditSnapshot) {
                    // Get credit balance that will be automatically applied
                    final creditBalance = creditSnapshot.data ?? 0.0;
                    
                    // Only calculate new due if amount is actually entered
                    final hasAmountEntered = _amountController.text.isNotEmpty && 
                        double.tryParse(_amountController.text) != null;
                    final amountPaid = hasAmountEntered
                        ? double.tryParse(_amountController.text)!
                        : 0.0;
                    
                    final existingDueTotal = _isLoadingDuePayments
                        ? 0.0
                        : _duePayments.fold(0.0, (sum, p) => sum + p.dueAmount);
                    
                    // IMPORTANT: Credit balance is automatically applied to current sale
                    // So the effective sale amount after credit = saleAmount - creditBalance
                    final saleAmountAfterCredit = (widget.cart.totalAmount - creditBalance).clamp(0.0, widget.cart.totalAmount);
                    
                    // Only calculate new due if amount is entered AND it's less than sale amount after credit
                    final newDueAmount = hasAmountEntered && amountPaid < saleAmountAfterCredit
                        ? saleAmountAfterCredit - amountPaid
                        : 0.0;
                    
                    // Subtotal = Current Sale (after credit) + Existing Due Payments
                    // This shows what the customer actually needs to pay
                    final subtotal = saleAmountAfterCredit + existingDueTotal;
                    
                    // Total Due After Payment = Remaining Sale (after credit) + Existing Due + New Due (if partial payment)
                    final totalDueAfterPayment = saleAmountAfterCredit + existingDueTotal + newDueAmount;
                    
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  'Subtotal (Sale + Existing Due):',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatter.format(subtotal),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          // Only show "Total Due After This Payment" if amount is entered
                          if (hasAmountEntered && newDueAmount > 0) ...[
                            const SizedBox(height: 8),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Total Due After This Payment:',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatter.format(totalDueAfterPayment),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ] else if (hasAmountEntered && amountPaid >= widget.cart.totalAmount && existingDueTotal > 0) ...[
                            // Full payment made, but there are existing dues
                            const SizedBox(height: 8),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Remaining Due (Existing):',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatter.format(existingDueTotal),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),
              // Seller Selection Section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seller (Optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<Seller>>(
                    stream: _sellerService.getSellersStream(),
                    builder: (context, snapshot) {
                      final allSellers = snapshot.data ?? [];
                      final query = _sellerSearchController.text.toLowerCase().trim();
                      _filteredSellers = query.isEmpty
                          ? []
                          : allSellers
                              .where((seller) {
                                // Only show sellers that have at least phone or location (name is always required)
                                final hasPhone = seller.phone != null && seller.phone!.isNotEmpty;
                                final hasLocation = seller.location != null && seller.location!.isNotEmpty;
                                
                                // Must have at least phone or location to be shown
                                if (!hasPhone && !hasLocation) {
                                  return false;
                                }
                                
                                // Check if search query matches name, phone, or location
                                final nameMatches = seller.name.toLowerCase().contains(query);
                                final phoneMatches = hasPhone && seller.phone!.toLowerCase().contains(query);
                                final locationMatches = hasLocation && seller.location!.toLowerCase().contains(query);
                                
                                // Only show if query matches at least one field
                                return nameMatches || phoneMatches || locationMatches;
                              })
                              .toList();

                      return Column(
                        children: [
                          TextField(
                            controller: _sellerSearchController,
                            focusNode: _sellerFocusNode,
                            decoration: InputDecoration(
                              hintText: _selectedSeller != null
                                  ? _selectedSeller!.name
                                  : 'Search seller by name, phone, or location...',
                              prefixIcon: const Icon(Icons.person_search),
                              suffixIcon: _selectedSeller != null
                                  ? IconButton(
                                      icon: const Icon(Icons.close, size: 20),
                                      onPressed: () {
                                        setState(() {
                                          _selectedSeller = null;
                                          _sellerSearchController.clear();
                                        });
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            onTap: () {
                              if (_selectedSeller != null) {
                                setState(() {
                                  _selectedSeller = null;
                                  _sellerSearchController.clear();
                                });
                              }
                            },
                          ),
                          // Dropdown list
                          if (_isDropdownOpen &&
                              _sellerSearchController.text.isNotEmpty &&
                              _filteredSellers.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                // Prevent tap from propagating and closing dropdown
                                debugPrint('Dropdown container tapped - preventing close');
                              },
                              child: Container(
                                margin: const EdgeInsets.only(top: 4),
                                constraints: const BoxConstraints(maxHeight: 200),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _filteredSellers.length,
                                  itemBuilder: (context, index) {
                                    final seller = _filteredSellers[index];
                                    debugPrint('Building ListTile for seller: ${seller.name} at index $index');
                                    return MouseRegion(
                                      onEnter: (_) {
                                        debugPrint('Mouse entered seller: ${seller.name}');
                                      },
                                      child: GestureDetector(
                                        onTap: () async {
                                          debugPrint('=== SELLER SELECTION START ===');
                                          debugPrint('Seller tapped: ${seller.name}');
                                          debugPrint('Seller ID: ${seller.id}');
                                          
                                          // Update state inside setDialogState to trigger rebuild
                                          if (_dialogStateSetter != null) {
                                            debugPrint('Calling _dialogStateSetter');
                                            _dialogStateSetter!(() {
                                              debugPrint('Inside setDialogState - setting seller to: ${seller.name}');
                                              _selectedSeller = seller;
                                              _sellerSearchController.clear();
                                              _sellerFocusNode.unfocus();
                                              _isDropdownOpen = false;
                                              _isLoadingDuePayments = true;
                                              _duePayments = [];
                                            });
                                            
                                            // Fetch due payments for selected seller
                                            try {
                                              final duePayments = await _sellerService.getDuePaymentsForSeller(seller.id);
                                              _dialogStateSetter!(() {
                                                _duePayments = duePayments;
                                                _isLoadingDuePayments = false;
                                              });
                                              debugPrint('Fetched ${duePayments.length} due payments for seller: ${seller.name}');
                                            } catch (e) {
                                              debugPrint('Error fetching due payments: $e');
                                              _dialogStateSetter!(() {
                                                _duePayments = [];
                                                _isLoadingDuePayments = false;
                                              });
                                            }
                                            
                                            debugPrint('After setDialogState call - _selectedSeller: ${_selectedSeller?.name}');
                                          } else {
                                            debugPrint('_dialogStateSetter is null, using setState');
                                            setState(() {
                                              debugPrint('Inside setState - setting seller to: ${seller.name}');
                                              _selectedSeller = seller;
                                              _sellerSearchController.clear();
                                              _sellerFocusNode.unfocus();
                                              _isDropdownOpen = false;
                                              _isLoadingDuePayments = true;
                                              _duePayments = [];
                                            });
                                            
                                            // Fetch due payments for selected seller
                                            try {
                                              final duePayments = await _sellerService.getDuePaymentsForSeller(seller.id);
                                              setState(() {
                                                _duePayments = duePayments;
                                                _isLoadingDuePayments = false;
                                              });
                                              debugPrint('Fetched ${duePayments.length} due payments for seller: ${seller.name}');
                                            } catch (e) {
                                              debugPrint('Error fetching due payments: $e');
                                              setState(() {
                                                _duePayments = [];
                                                _isLoadingDuePayments = false;
                                              });
                                            }
                                          }
                                          
                                          debugPrint('After updates - _selectedSeller is now: ${_selectedSeller?.name}');
                                          debugPrint('=== SELLER SELECTION END ===');
                                        },
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: Colors.green.shade100,
                                            child: Icon(Icons.person,
                                                color: Colors.green.shade700, size: 20),
                                          ),
                                          title: Text(
                                            seller.name,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                                              if (seller.phone != null)
                                                Text(
                                                  seller.phone!,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                              if (seller.location != null)
                                                Text(
                                                  seller.location!,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              // Selected seller text - outside StreamBuilder for real-time updates
              if (_selectedSeller != null)
                Container(
                  key: ValueKey('selected-seller-${_selectedSeller!.id}'),
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200!, width: 2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Selected Seller: ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _selectedSeller!.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: Colors.grey[600]),
                        onPressed: () {
                          debugPrint('Seller deselected: ${_selectedSeller?.name}');
                          if (_dialogStateSetter != null) {
                            _dialogStateSetter!(() {
                              _selectedSeller = null;
                              _sellerSearchController.clear();
                              _isDropdownOpen = false;
                              _duePayments = [];
                              _isLoadingDuePayments = false;
                            });
                          } else {
                            setState(() {
                              _selectedSeller = null;
                              _sellerSearchController.clear();
                              _isDropdownOpen = false;
                              _duePayments = [];
                              _isLoadingDuePayments = false;
                            });
                          }
                        },
                        tooltip: 'Remove seller',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              TextField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount Paid',
                  hintText: '0.00',
                  prefixText: 'Rs. ',
                  prefixIcon: const Icon(Icons.money),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                autofocus: true,
                onChanged: (value) {
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
              // Quick amount buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: quickAmounts.map((amount) {
                  return OutlinedButton(
                    onPressed: () {
                      _amountController.text = amount.toString();
                      setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(formatter.format(amount)),
                  );
                }).toList(),
                    ),
                    const SizedBox(height: 16),
              // Show change/new due payment if amount is entered
              if (_amountController.text.isNotEmpty)
                FutureBuilder<double>(
                  future: _selectedSeller != null
                      ? _sellerService.getCreditBalance(_selectedSeller!.id)
                      : Future.value(0.0),
                  builder: (context, creditSnapshot) {
                    // Get credit balance that will be automatically applied
                    final creditBalance = creditSnapshot.data ?? 0.0;
                    
                    final hasAmountEntered = _amountController.text.isNotEmpty && 
                        double.tryParse(_amountController.text) != null;
                    final amountPaid = hasAmountEntered
                        ? double.tryParse(_amountController.text)!
                        : 0.0;
                    
                    // Calculate existing due total
                    final existingDueTotal = _isLoadingDuePayments
                        ? 0.0
                        : _duePayments.fold(0.0, (sum, p) => sum + p.dueAmount);
                    
                    // IMPORTANT: Credit balance is automatically applied to current sale
                    // So the effective sale amount after credit = saleAmount - creditBalance
                    final saleAmountAfterCredit = _selectedSeller != null
                        ? (widget.cart.totalAmount - creditBalance).clamp(0.0, widget.cart.totalAmount)
                        : widget.cart.totalAmount;
                    
                    // If seller is selected, calculate change based on subtotal (current sale after credit + existing due)
                    // Otherwise, calculate change based on current sale only
                    final totalToPay = _selectedSeller != null
                        ? saleAmountAfterCredit + existingDueTotal
                        : widget.cart.totalAmount;
                    
                    final change = amountPaid - totalToPay;
                    
                    // New due amount only applies to current sale (after credit), not existing dues
                    final newDueAmount = _selectedSeller != null && amountPaid < saleAmountAfterCredit
                        ? saleAmountAfterCredit - amountPaid
                        : 0.0;
                    
                    return Column(
                      children: [
                        // Change/Borrow display
                    Container(
                          padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                            color: change >= 0 ? Colors.blue.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: change >= 0 
                                ? Border.all(color: Colors.blue.shade200!)
                                : Border.all(color: Colors.orange.shade200!),
                      ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    change >= 0 ? Icons.money_off : Icons.account_balance_wallet,
                                    color: change >= 0 ? Colors.blue.shade700 : Colors.orange.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    change >= 0 ? 'Change' : 'Borrow',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: change >= 0 ? Colors.blue.shade900 : Colors.orange.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                formatter.format(change.abs()),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: change >= 0 ? Colors.blue.shade700 : Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // New due payment preview (if seller selected and partial payment on current sale)
                        if (_selectedSeller != null && newDueAmount > 0) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.purple.shade200!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.purple.shade700, size: 18),
                                    const SizedBox(width: 8),
                          Text(
                                      'New Due Payment (This Sale):',
                            style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.purple.shade900,
                            ),
                          ),
                        ],
                                ),
                                Text(
                                  formatter.format(newDueAmount),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
                          ),
                        ],
                      ],
                    );
                  },
              ),
              const SizedBox(height: 24),
              // Description field
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Add any notes or description...',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        final amountPaid = double.tryParse(_amountController.text) ?? 0;
                        
                        // Allow partial payment only if seller is selected
                        if (amountPaid < widget.cart.totalAmount && _selectedSeller == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Insufficient amount. Select a seller to allow partial payment.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        // Calculate existing due total
                        final existingDueTotal = _isLoadingDuePayments
                            ? 0.0
                            : _duePayments.fold(0.0, (sum, p) => sum + p.dueAmount);
                        
                        final description = _descriptionController.text.trim().isEmpty
                            ? null
                            : _descriptionController.text.trim();
                        
                        widget.onComplete(amountPaid, _selectedSeller?.id, existingDueTotal, description);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Complete Sale',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Color? color;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 18 : 15,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            color: isTotal ? Colors.black : (color ?? Colors.grey[700]),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 24 : 16,
            fontWeight: FontWeight.bold,
            color: isTotal ? (color ?? Colors.green.shade700) : (color ?? Colors.black87),
          ),
        ),
      ],
    );
  }
}



