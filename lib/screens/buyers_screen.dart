import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/buyer.dart';
import '../models/balance_entry.dart';
import '../services/buyer_service.dart';
import '../services/balance_service.dart';
import 'add_edit_buyer_screen.dart';
import 'buyer_bills_screen.dart';

class BuyersScreen extends StatefulWidget {
  const BuyersScreen({super.key});

  @override
  State<BuyersScreen> createState() => _BuyersScreenState();
}

class _BuyersScreenState extends State<BuyersScreen> {
  final BuyerService _buyerService = BuyerService();
  final BalanceService _balanceService = BalanceService();
  final TextEditingController _searchController = TextEditingController();
  List<Buyer>? _searchResults;
  int _currentPage = 1;
  static const int _itemsPerPage = 12;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _searchBuyers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _currentPage = 1; // Reset to first page when search is cleared
      });
      return;
    }

    final results = await _buyerService.searchBuyers(query);
    setState(() {
      _searchResults = results;
      _currentPage = 1; // Reset to first page when searching
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Summary Section with 3 metrics
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Total Revenue',
                    icon: Icons.trending_up,
                    color: Colors.green,
                    stream: _buyerService.getTotalRevenueFromSalesStream(),
                    showPlusIcon: true,
                    onPlusPressed: () => _showAddBalanceDialog(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Payable Payment',
                    icon: Icons.account_balance_wallet,
                    color: Colors.orange,
                    stream: _buyerService.getTotalPayablePaymentStream(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Deposit Balance',
                    icon: Icons.account_balance,
                    color: Colors.blue,
                    stream: _buyerService.getTotalDepositBalanceStream(),
                  ),
                ),
              ],
            ),
          ),
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search buyers...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchBuyers('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _searchBuyers,
            ),
          ),
          // Buyers List
          Expanded(
            child: StreamBuilder<List<Buyer>>(
              stream: _buyerService.getBuyersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final buyers = _searchResults ?? snapshot.data ?? [];

                if (buyers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No buyers yet'
                              : 'No buyers found',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchController.text.isEmpty
                              ? 'Add your first buyer to get started'
                              : 'Try a different search term',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                // Calculate pagination
                final totalPages = (buyers.length / _itemsPerPage).ceil();
                final startIndex = (_currentPage - 1) * _itemsPerPage;
                final endIndex = (startIndex + _itemsPerPage).clamp(0, buyers.length);
                final paginatedBuyers = buyers.sublist(startIndex, endIndex);

                // Reset to first page if current page is out of bounds
                if (_currentPage > totalPages && totalPages > 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    setState(() {
                      _currentPage = 1;
                    });
                  });
                }

                return Column(
                  children: [
                    // Buyers List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: paginatedBuyers.length,
                        itemBuilder: (context, index) {
                          final buyer = paginatedBuyers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            // Leading icon
                            CircleAvatar(
                              backgroundColor: Colors.purple.shade100,
                              child: Icon(
                                Icons.person,
                                color: Colors.purple.shade700,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            
                            // Buyer info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    buyer.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  if (buyer.phone != null) ...[
                                    Row(
                                      children: [
                                        Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                                        const SizedBox(width: 4),
                                        Text(
                                          buyer.phone!,
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                  if (buyer.location != null) ...[
                                    Row(
                                      children: [
                                        Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            buyer.location!,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                  if (buyer.shopNo != null) ...[
                                    Row(
                                      children: [
                                        Icon(Icons.store, size: 14, color: Colors.grey[600]),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Shop No: ${buyer.shopNo}',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                ],
                              ),
                            ),
                            
                            // Due Balance with real-time updates (before view icon)
                            StreamBuilder<double>(
                              stream: _buyerService.getDueBalanceStream(buyer.id),
                              builder: (context, balanceSnapshot) {
                                final dueBalance = balanceSnapshot.data ?? 0.0;
                                if (dueBalance > 0) {
                                  return Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.orange.shade300,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.account_balance_wallet,
                                          size: 14,
                                          color: Colors.orange[700],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          dueBalance.toStringAsFixed(2),
                                          style: TextStyle(
                                            color: Colors.orange[700],
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            
                            // Actions
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ActionButton(
                                  icon: Icons.visibility,
                                  color: Colors.green,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            BuyerBillsScreen(buyer: buyer),
                                      ),
                                    );
                                  },
                                  tooltip: 'View Bills',
                                ),
                                _ActionButton(
                                  icon: Icons.edit,
                                  color: Colors.blue,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            AddEditBuyerScreen(buyer: buyer),
                                      ),
                                    );
                                  },
                                  tooltip: 'Edit',
                                ),
                                _ActionButton(
                                  icon: Icons.delete,
                                  color: Colors.red,
                                  onPressed: () => _deleteBuyer(context, buyer),
                                  tooltip: 'Delete',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                        },
                      ),
                    ),
                    // Pagination Controls
                    if (totalPages > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 2,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Previous Button
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: _currentPage > 1
                                  ? () {
                                      setState(() {
                                        _currentPage--;
                                      });
                                    }
                                  : null,
                              tooltip: 'Previous',
                            ),
                            const SizedBox(width: 8),
                            // Page Numbers
                            ...List.generate(
                              totalPages > 7 ? 7 : totalPages,
                              (index) {
                                int pageNumber;
                                if (totalPages <= 7) {
                                  pageNumber = index + 1;
                                } else {
                                  // Show first, last, and pages around current
                                  if (_currentPage <= 4) {
                                    pageNumber = index + 1;
                                  } else if (_currentPage >= totalPages - 3) {
                                    pageNumber = totalPages - 6 + index;
                                  } else {
                                    pageNumber = _currentPage - 3 + index;
                                  }
                                }
                                
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _currentPage = pageNumber;
                                      });
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _currentPage == pageNumber
                                            ? Colors.blue
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _currentPage == pageNumber
                                              ? Colors.blue
                                              : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '$pageNumber',
                                          style: TextStyle(
                                            color: _currentPage == pageNumber
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: _currentPage == pageNumber
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            // Next Button
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _currentPage < totalPages
                                  ? () {
                                      setState(() {
                                        _currentPage++;
                                      });
                                    }
                                  : null,
                              tooltip: 'Next',
                            ),
                          ],
                        ),
                      ),
                    // Page Info
                    if (totalPages > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        color: Colors.grey[50],
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Page $_currentPage of $totalPages',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Showing ${startIndex + 1}-${startIndex + paginatedBuyers.length} of ${buyers.length} buyers',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddEditBuyerScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Buyer'),
        backgroundColor: Colors.purple,
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required IconData icon,
    required Color color,
    required Stream<double> stream,
    bool showPlusIcon = false,
    VoidCallback? onPlusPressed,
  }) {
    return StreamBuilder<double>(
      stream: stream,
      builder: (context, snapshot) {
        final value = snapshot.data ?? 0.0;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showPlusIcon && onPlusPressed != null)
                    InkWell(
                      onTap: onPlusPressed,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add,
                          size: 16,
                          color: color,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (isLoading)
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Text(
                  value.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAddBalanceDialog(BuildContext context) {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.green),
              const SizedBox(width: 12),
              const Text('Add Balance'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount *',
                    hintText: 'Enter amount',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Enter description',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (pickedDate != null) {
                      setState(() {
                        selectedDate = pickedDate;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date *',
                      prefixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      DateFormat('yyyy-MM-dd').format(selectedDate),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (amountController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter amount'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final amount = double.tryParse(amountController.text);
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a valid amount'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setState(() {
                        isLoading = true;
                      });

                      try {
                        final balanceEntry = BalanceEntry(
                          id: const Uuid().v4(),
                          amount: amount,
                          description: descriptionController.text.trim().isEmpty
                              ? null
                              : descriptionController.text.trim(),
                          date: selectedDate,
                          createdAt: DateTime.now(),
                        );

                        await _balanceService.addBalanceEntry(balanceEntry);

                        if (context.mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Balance of ${amount.toStringAsFixed(2)} added successfully',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setState(() {
                            isLoading = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error adding balance: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(isLoading ? 'Adding...' : 'Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteBuyer(BuildContext context, Buyer buyer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Buyer'),
        content: Text('Are you sure you want to delete "${buyer.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _buyerService.deleteBuyer(buyer.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Buyer deleted')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
      ),
    );
  }
}
