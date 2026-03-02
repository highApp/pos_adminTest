import 'package:flutter/material.dart';
import '../models/seller.dart';
import '../services/seller_service.dart';
import '../screens/seller_history_screen.dart';

/// Dialog to search sellers and open History, Add Manual Due Payment, or Add Manual Sale.
/// Can be opened via shortcut (e.g. Ctrl+Shift+S) from anywhere in the admin panel.
class SellersQuickAccessDialog extends StatefulWidget {
  const SellersQuickAccessDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SellersQuickAccessDialog(),
    );
  }

  @override
  State<SellersQuickAccessDialog> createState() => _SellersQuickAccessDialogState();
}

class _SellersQuickAccessDialogState extends State<SellersQuickAccessDialog> {
  final SellerService _sellerService = SellerService();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSeller(Seller seller, {String? action}) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SellerHistoryScreen(
          seller: seller,
          initialAction: action,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.person_search, color: Colors.purple.shade700),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sellers Quick Access',
              style: TextStyle(fontSize: 20),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search sellers by name or code...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a seller, then open history or add due payment / manual sale.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<Seller>>(
                stream: _sellerService.getSellersStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  var sellers = snapshot.data ?? [];
                  if (_query.isNotEmpty) {
                    sellers = sellers.where((s) {
                      final name = s.name.toLowerCase();
                      final code = (s.code ?? '').toLowerCase();
                      return name.contains(_query) || code.contains(_query);
                    }).toList();
                  }
                  if (sellers.isEmpty) {
                    return Center(
                      child: Text(
                        _query.isEmpty ? 'No sellers' : 'No sellers match "$_query"',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: sellers.length,
                    itemBuilder: (context, i) {
                      final seller = sellers[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.shade100,
                            child: Text(
                              seller.name.isNotEmpty ? seller.name[0].toUpperCase() : '?',
                              style: TextStyle(color: Colors.purple.shade700),
                            ),
                          ),
                          title: Text(
                            seller.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: seller.code != null && seller.code!.isNotEmpty
                              ? Text(seller.code!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                              : null,
                          trailing: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            children: [
                              Tooltip(
                                message: 'Open history',
                                child: IconButton(
                                  icon: const Icon(Icons.history, size: 20),
                                  onPressed: () => _openSeller(seller),
                                ),
                              ),
                              Tooltip(
                                message: 'Add manual due payment',
                                child: IconButton(
                                  icon: Icon(Icons.pending_actions, size: 20, color: Colors.orange.shade700),
                                  onPressed: () => _openSeller(seller, action: 'due_payment'),
                                ),
                              ),
                              Tooltip(
                                message: 'Add manual sale',
                                child: IconButton(
                                  icon: Icon(Icons.add_shopping_cart, size: 20, color: Colors.green.shade700),
                                  onPressed: () => _openSeller(seller, action: 'manual_sale'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
