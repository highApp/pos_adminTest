import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/cart_provider.dart';

/// Bottom sheet: enter **sale price per unit** (pre-filled from cart, matches
/// Regular vs Wholesale) and **amount to spend** → quantity = amount ÷ price.
class CartWeightCalculatorSheet extends StatefulWidget {
  final CartItem cartItem;

  const CartWeightCalculatorSheet({super.key, required this.cartItem});

  static Future<double?> show(
    BuildContext context, {
    required CartItem cartItem,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: CartWeightCalculatorSheet(cartItem: cartItem),
      ),
    );
  }

  @override
  State<CartWeightCalculatorSheet> createState() =>
      _CartWeightCalculatorSheetState();
}

class _CartWeightCalculatorSheetState extends State<CartWeightCalculatorSheet> {
  late final TextEditingController _priceController;
  late final TextEditingController _amountController;

  /// Per-unit price used in cart math (Regular → [salePrice], Wholesale → wholesale/dozen-piece/bundle-piece).
  double get _catalogUnitPrice => widget.cartItem.unitPrice;

  String get _unitDisplay {
    final u = widget.cartItem.product.unit.trim();
    return u.isEmpty ? 'unit' : u;
  }

  String get _salePriceLabel {
    final u = _unitDisplay.toLowerCase();
    if (u == 'kg' || u == 'kilogram') return 'Sale price per KG';
    if (u == 'g' || u == 'gm' || u == 'gram' || u == 'grams') {
      return 'Sale price per g';
    }
    if (u == 'l' || u == 'liter' || u == 'litre') return 'Sale price per L';
    if (u == 'ml') return 'Sale price per ml';
    return 'Sale price per $_unitDisplay';
  }

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: _formatMoneyField(_catalogUnitPrice),
    );
    _amountController = TextEditingController();
  }

  /// Re-sync if parent ever reopens with same widget instance (unlikely).
  @override
  void didUpdateWidget(covariant CartWeightCalculatorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cartItem.unitPrice != widget.cartItem.unitPrice ||
        oldWidget.cartItem.saleType != widget.cartItem.saleType) {
      _priceController.text = _formatMoneyField(widget.cartItem.unitPrice);
    }
  }

  String _formatMoneyField(double v) {
    if (v.isNaN || v.isInfinite) return '';
    return v.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _priceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _apply() {
    final price = double.tryParse(_priceController.text.trim());
    final spend = double.tryParse(_amountController.text.trim());
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid sale price greater than zero'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (spend == null || spend <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount to spend'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final qty = spend / price;
    if (qty.isNaN || qty.isInfinite || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not compute quantity'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).pop(qty);
  }

  static final _decimalInput = FilteringTextInputFormatter.allow(
    RegExp(r'^\d*\.?\d{0,4}'),
  );

  @override
  Widget build(BuildContext context) {
    final item = widget.cartItem;
    final isWholesale = item.saleType == SaleType.wholesale;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        8,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.scale_outlined, color: Colors.green.shade700, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Weight Calculator',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: Icon(
                  isWholesale ? Icons.business : Icons.shopping_bag,
                  size: 18,
                  color: isWholesale ? Colors.indigo : Colors.green.shade700,
                ),
                label: Text(isWholesale ? 'Wholesale' : 'Regular sale'),
                backgroundColor: isWholesale
                    ? Colors.indigo.shade50
                    : Colors.green.shade50,
                side: BorderSide(
                  color: isWholesale
                      ? Colors.indigo.shade200
                      : Colors.green.shade200,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              Text(
                item.product.name,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Price matches your current sale type. Quantity = amount ÷ price per $_unitDisplay.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Text(
            '$_salePriceLabel *',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_decimalInput],
            decoration: InputDecoration(
              prefixText: 'Rs. ',
              hintText: '0.00',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Amount to Spend *',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_decimalInput],
            decoration: InputDecoration(
              prefixText: 'Rs. ',
              hintText: '0.00',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
