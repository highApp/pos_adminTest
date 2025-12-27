import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/buyer.dart';
import '../services/buyer_service.dart';

class AddEditBuyerScreen extends StatefulWidget {
  final Buyer? buyer;

  const AddEditBuyerScreen({super.key, this.buyer});

  @override
  State<AddEditBuyerScreen> createState() => _AddEditBuyerScreenState();
}

class _AddEditBuyerScreenState extends State<AddEditBuyerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _buyerService = BuyerService();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _locationController;
  late TextEditingController _shopNoController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.buyer?.name ?? '');
    _phoneController = TextEditingController(text: widget.buyer?.phone ?? '');
    _locationController = TextEditingController(text: widget.buyer?.location ?? '');
    _shopNoController = TextEditingController(text: widget.buyer?.shopNo ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _shopNoController.dispose();
    super.dispose();
  }

  Future<void> _saveBuyer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final buyer = Buyer(
        id: widget.buyer?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        shopNo: _shopNoController.text.trim().isEmpty
            ? null
            : _shopNoController.text.trim(),
        createdAt: widget.buyer?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (widget.buyer == null) {
        await _buyerService.addBuyer(buyer);
      } else {
        await _buyerService.updateBuyer(buyer);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.buyer == null
                  ? 'Buyer added successfully'
                  : 'Buyer updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
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
        title: Text(widget.buyer == null ? 'Add Buyer' : 'Edit Buyer'),
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
                labelText: 'Buyer Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter buyer name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
                hintText: 'e.g., 03001234567',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
                hintText: 'e.g., Shop 1, Market Street',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _shopNoController,
              decoration: const InputDecoration(
                labelText: 'Shop No',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
                hintText: 'e.g., 12, A-5',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveBuyer,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(widget.buyer == null ? 'Add Buyer' : 'Update Buyer'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
