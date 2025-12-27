import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/borrow.dart';
import '../services/borrow_service.dart';

class BorrowsScreen extends StatefulWidget {
  const BorrowsScreen({super.key});

  @override
  State<BorrowsScreen> createState() => _BorrowsScreenState();
}

class _BorrowsScreenState extends State<BorrowsScreen> {
  final borrowService = BorrowService();
  String _filterType = 'all'; // 'all', 'borrowed', 'lent'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header with Add Button and Filter
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Borrows',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddBorrowDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Borrow'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Filter buttons
                Row(
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _filterType == 'all',
                      onTap: () => setState(() => _filterType = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Borrowed',
                      selected: _filterType == 'borrowed',
                      onTap: () => setState(() => _filterType = 'borrowed'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Lent',
                      selected: _filterType == 'lent',
                      onTap: () => setState(() => _filterType = 'lent'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Borrows List
          Expanded(
            child: StreamBuilder<List<Borrow>>(
              stream: borrowService.getBorrowsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var borrows = snapshot.data!;
                
                // Filter by type
                if (_filterType != 'all') {
                  borrows = borrows.where((b) => b.type == _filterType).toList();
                }

                if (borrows.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.account_balance_wallet,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No borrows yet',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap "Add Borrow" to get started',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: borrows.length,
                  itemBuilder: (context, index) {
                    final borrow = borrows[index];
                    return _buildBorrowCard(borrow);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBorrowCard(Borrow borrow) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final dateFormatter = DateFormat('MMM dd, yyyy • hh:mm a');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borrow.isPaid ? Colors.green.shade200 : Colors.orange.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: borrow.isPaid 
                ? Colors.green.shade50 
                : (borrow.type == 'borrowed' ? Colors.blue.shade50 : Colors.orange.shade50),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            borrow.typeIcon,
            style: const TextStyle(fontSize: 24),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                borrow.personName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  decoration: borrow.isPaid ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (borrow.isPaid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Paid',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: borrow.type == 'borrowed' 
                        ? Colors.blue.shade50 
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    borrow.typeDisplayName,
                    style: TextStyle(
                      color: borrow.type == 'borrowed' 
                          ? Colors.blue.shade700 
                          : Colors.orange.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (borrow.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                borrow.description,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              dateFormatter.format(borrow.createdAt),
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
            if (borrow.isPaid && borrow.paidAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Paid on: ${dateFormatter.format(borrow.paidAt!)}',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatter.format(borrow.amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: borrow.type == 'borrowed' 
                    ? Colors.blue[700] 
                    : Colors.orange[700],
              ),
            ),
          ],
        ),
        onTap: () => _showEditBorrowDialog(borrow),
        onLongPress: borrow.isPaid ? null : () {
          if (borrow.type == 'lent') {
            _showMarkAsPaidDialog(borrow);
          }
        },
      ),
    );
  }

  void _showAddBorrowDialog() {
    _showBorrowDialog();
  }

  void _showEditBorrowDialog(Borrow borrow) {
    _showBorrowDialog(borrow: borrow);
  }

  void _showBorrowDialog({Borrow? borrow}) {
    final isEditing = borrow != null;
    final personNameController = TextEditingController(text: borrow?.personName ?? '');
    final descriptionController = TextEditingController(text: borrow?.description ?? '');
    final amountController = TextEditingController(text: borrow?.amount.toString() ?? '');
    String selectedType = borrow?.type ?? 'borrowed';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Borrow' : 'Add Borrow'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type Selection
                const Text(
                  'Type',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _TypeChip(
                        label: 'Borrowed',
                        icon: '📥',
                        value: 'borrowed',
                        selected: selectedType == 'borrowed',
                        onTap: () {
                          setDialogState(() {
                            selectedType = 'borrowed';
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TypeChip(
                        label: 'Lent',
                        icon: '📤',
                        value: 'lent',
                        selected: selectedType == 'lent',
                        onTap: () {
                          setDialogState(() {
                            selectedType = 'lent';
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Person Name
                TextField(
                  controller: personNameController,
                  decoration: const InputDecoration(
                    labelText: 'Person Name *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                // Description
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                // Amount
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.currency_rupee),
                    prefixText: 'Rs. ',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (personNameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter person name'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid amount'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final newBorrow = Borrow(
                  id: borrow?.id ?? const Uuid().v4(),
                  type: selectedType,
                  personName: personNameController.text.trim(),
                  description: descriptionController.text.trim(),
                  amount: amount,
                  createdAt: borrow?.createdAt ?? DateTime.now(),
                  isPaid: borrow?.isPaid ?? false,
                  paidAt: borrow?.paidAt,
                );

                try {
                  if (isEditing) {
                    await borrowService.updateBorrow(newBorrow);
                  } else {
                    await borrowService.addBorrow(newBorrow);
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEditing ? 'Borrow updated' : 'Borrow added'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(isEditing ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMarkAsPaidDialog(Borrow borrow) {
    if (borrow.type != 'lent') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only lent borrows can be marked as paid'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    DateTime? selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mark as Paid'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mark this borrow payment as paid? This will increase revenue and recovery balance.',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setDialogState(() {
                      selectedDate = picked;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Payment Date *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    selectedDate != null
                        ? DateFormat('MMM dd, yyyy').format(selectedDate!)
                        : 'Select date',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select payment date'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                try {
                  await borrowService.markBorrowAsPaid(borrow, selectedDate!);
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Borrow marked as paid. Revenue and recovery balance updated.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Mark as Paid'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Colors.grey[200],
          border: Border.all(
            color: selected
                ? Theme.of(context).primaryColor
                : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected
                ? Theme.of(context).primaryColor
                : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final String icon;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Colors.grey[200],
          border: Border.all(
            color: selected
                ? Theme.of(context).primaryColor
                : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? Theme.of(context).primaryColor
                    : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

