import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/seller.dart';
import '../models/seller_reminder.dart';
import '../services/seller_service.dart';
import '../services/seller_reminder_service.dart';
import '../services/csv_export_service.dart';
// Web download helper - use stub on mobile
import '../utils/html_stub.dart' as html;
import 'seller_history_screen.dart';

class SellersScreen extends StatefulWidget {
  const SellersScreen({super.key});

  @override
  State<SellersScreen> createState() => _SellersScreenState();
}

class _SellersScreenState extends State<SellersScreen> {
  final SellerService _sellerService = SellerService();
  final SellerReminderService _reminderService = SellerReminderService();
  final CsvExportService _csvExportService = CsvExportService();
  bool _reminderBannerDismissed = false;
  final NumberFormat _currencyFormatter = NumberFormat.currency(symbol: 'Rs. ');
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 1;
  static const int _itemsPerPage = 12;
  bool _isExporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _searchSellers(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _currentPage = 1; // Reset to first page when searching
    });
  }

  List<Seller> _getPaginatedSellers(List<Seller> sellers) {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;
    return sellers.sublist(
      startIndex,
      endIndex > sellers.length ? sellers.length : endIndex,
    );
  }

  int _getTotalPages(int totalItems) {
    return (totalItems / _itemsPerPage).ceil();
  }

  List<Seller> _filterSellers(List<Seller> sellers) {
    if (_searchQuery.isEmpty) {
      return sellers;
    }
    
    return sellers.where((seller) {
      final name = seller.name.toLowerCase();
      final code = seller.code?.toLowerCase() ?? '';
      return name.contains(_searchQuery) || code.contains(_searchQuery);
    }).toList();
  }

  // Hash password using SHA-256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> _downloadFileWeb(String csvString, String filename) async {
    // Web download - direct implementation
    if (!kIsWeb) {
      return false;
    }
    
    try {
      debugPrint('Attempting to download CSV: $filename');
      debugPrint('CSV length: ${csvString.length} characters');
      
      // Direct web download implementation using dart:html
      final bytes = utf8.encode(csvString);
      
      // Try blob URL method first
      try {
        final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
        final url = html.Url.createObjectUrlFromBlob(blob);
        
        // Create anchor element
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..style.display = 'none';
        
        // Add to DOM
        final body = html.document.body;
        if (body != null) {
          body.append(anchor);
          
          // Trigger download
          anchor.click();
          debugPrint('Download click triggered via blob URL');
          
          // Clean up after a delay
          Future.delayed(const Duration(milliseconds: 300), () {
            try {
              if (anchor.parent != null) {
                anchor.remove();
              }
              html.Url.revokeObjectUrl(url);
              debugPrint('Download cleanup completed');
            } catch (e) {
              debugPrint('Error cleaning up download: $e');
            }
          });
          
          return true;
        }
      } catch (e) {
        debugPrint('Blob URL method failed: $e, trying data URI method');
      }
      
      // Fallback: Use data URI method
      try {
        final base64 = base64Encode(bytes);
        final dataUri = 'data:text/csv;charset=utf-8;base64,$base64';
        final anchor = html.AnchorElement(href: dataUri)
          ..setAttribute('download', filename)
          ..style.display = 'none';
        
        final body = html.document.body;
        if (body != null) {
          body.append(anchor);
          anchor.click();
          debugPrint('Download click triggered via data URI');
          
          Future.delayed(const Duration(milliseconds: 100), () {
            try {
              if (anchor.parent != null) {
                anchor.remove();
              }
            } catch (e) {
              debugPrint('Error cleaning up data URI anchor: $e');
            }
          });
          
          return true;
        }
      } catch (e) {
        debugPrint('Data URI method also failed: $e');
      }
      
      // If both methods fail, show dialog
      if (mounted) {
        _showCsvDialog(context, csvString, filename);
      }
      return false;
      
    } catch (e, stackTrace) {
      debugPrint('Error downloading CSV: $e');
      debugPrint('Stack trace: $stackTrace');
      // Fallback: Show dialog if download fails
      if (mounted) {
        _showCsvDialog(context, csvString, filename);
      }
      return false;
    }
  }

  void _showCsvDialog(BuildContext context, String csvString, String filename) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text('CSV Export', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('CSV data generated. Copy the content below:'),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: SingleChildScrollView(
                  child: SelectableText(
                    csvString,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: csvString));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('CSV data copied to clipboard'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    child: const Text('Copy to Clipboard'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToCsv(List<Seller> sellers) async {
    if (_isExporting) {
      debugPrint('Export already in progress');
      return;
    }
    
    if (sellers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No sellers to export'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    setState(() {
      _isExporting = true;
    });

    try {
      debugPrint('Starting CSV export for ${sellers.length} sellers');
      
      if (kIsWeb) {
        // Web: Generate CSV and trigger download
        final csvString = await _csvExportService.getSellersCsvString(
          sellers: sellers,
          searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        );
        
        debugPrint('CSV string generated, length: ${csvString.length}');
        
        final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
        final filename = _searchQuery.isNotEmpty
            ? 'sellers_export_${_searchQuery.replaceAll(' ', '_')}_$timestamp.csv'
            : 'sellers_export_$timestamp.csv';
        
        debugPrint('Filename: $filename');
        
        // Download CSV file for web
        final downloadSuccess = await _downloadFileWeb(csvString, filename);
        
        if (mounted) {
          if (downloadSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Sellers exported successfully: $filename'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Download failed. CSV data is available in the dialog.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        // Mobile: Use the service method
        await _csvExportService.exportSellersToCsv(
          sellers: sellers,
          context: context,
          searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error in _exportToCsv: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting sellers: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sellers'),
        elevation: 0,
        actions: [
          StreamBuilder<List<Seller>>(
            stream: _sellerService.getSellersStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              
              final allSellers = snapshot.data ?? [];
              final filteredSellers = _filterSellers(allSellers);
              
              if (filteredSellers.isEmpty) {
                return const SizedBox.shrink();
              }
              
              return IconButton(
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.download),
                onPressed: _isExporting
                    ? null
                    : () => _exportToCsv(filteredSellers),
                tooltip: 'Export to CSV',
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search sellers by name or code...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchSellers('');
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
              onChanged: _searchSellers,
            ),
          ),
          // Alert reminder banner for today's reminders
          if (!_reminderBannerDismissed)
            StreamBuilder<List<SellerReminder>>(
              stream: _reminderService.getRemindersDueTodayStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                final reminders = snapshot.data!;
                return Material(
                  color: Colors.amber.shade50,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_active,
                            color: Colors.amber.shade800,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${reminders.length} reminder${reminders.length > 1 ? 's' : ''} due today',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  reminders
                                      .take(2)
                                      .map((r) => r.message)
                                      .join(' • '),
                                  style: TextStyle(
                                    color: Colors.amber.shade800,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() => _reminderBannerDismissed = true);
                            },
                            icon: const Icon(Icons.close),
                            iconSize: 24,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            tooltip: 'Dismiss',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          // Sellers List
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

                final allSellers = snapshot.data ?? [];
                final filteredSellers = _filterSellers(allSellers);
                final totalPages = _getTotalPages(filteredSellers.length);
                
                // Ensure current page is valid
                if (_currentPage > totalPages && totalPages > 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    setState(() {
                      _currentPage = totalPages;
                    });
                  });
                }

                if (allSellers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          'No sellers yet',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add your first seller to get started',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                if (filteredSellers.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          'No sellers found',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try a different search term',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                final paginatedSellers = _getPaginatedSellers(filteredSellers);
                final startIndex = (_currentPage - 1) * _itemsPerPage;

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: paginatedSellers.length,
                        itemBuilder: (context, index) {
                          final seller = paginatedSellers[index];
                          final sellerNumber = startIndex + index + 1; // 1-based numbering across pages
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      '$sellerNumber',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  title: SelectableText(
                    seller.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (seller.code != null)
                        Row(
                          children: [
                            const Icon(Icons.tag, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: SelectableText(
                                seller.code!,
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (seller.phone != null)
                        Row(
                          children: [
                            const Icon(Icons.phone, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: SelectableText(
                                seller.phone!,
                              ),
                            ),
                          ],
                        ),
                      if (seller.location != null)
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: SelectableText(
                                seller.location!,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      if (seller.reference != null && seller.reference!.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.receipt_long, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: SelectableText(
                                'Reference: ${seller.reference!}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Due Payment Display
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('seller_history')
                            .where('sellerId', isEqualTo: seller.id)
                            .snapshots(),
                        builder: (context, snapshot) {
                          double totalDue = 0.0;
                          if (snapshot.hasData) {
                            totalDue = snapshot.data!.docs.fold<double>(
                              0.0,
                              (sum, doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return sum + (data['duePayment'] ?? 0).toDouble();
                              },
                            );
                          }
                          
                          if (totalDue > 0) {
                            return InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SellerHistoryScreen(seller: seller),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Due',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SelectableText(
                                      _currencyFormatter.format(totalDue),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      StreamBuilder<List<SellerReminder>>(
                        stream: _reminderService.getRemindersForSellerStream(seller.id),
                        builder: (context, snapshot) {
                          final activeReminders = (snapshot.data ?? [])
                              .where((r) => !r.isCompleted)
                              .toList();
                          final hasReminders = activeReminders.isNotEmpty;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.notifications,
                                  color: hasReminders ? Colors.amber.shade700 : Colors.grey.shade600,
                                ),
                                onPressed: () => _showReminderDialog(seller),
                                tooltip: hasReminders
                                    ? '${activeReminders.length} reminder(s)'
                                    : 'Add reminder',
                                iconSize: 24,
                                padding: const EdgeInsets.all(10),
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                              ),
                              if (hasReminders)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade700,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    child: Text(
                                      '${activeReminders.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.visibility, color: Colors.green),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SellerHistoryScreen(seller: seller),
                          ),
                        ),
                        tooltip: 'View History',
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showEditSellerDialog(seller),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDeleteSeller(seller),
                        tooltip: 'Delete',
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
                              'Showing ${startIndex + 1}-${startIndex + paginatedSellers.length} of ${filteredSellers.length} sellers',
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "import",
            onPressed: _showBatchImportDialog,
            backgroundColor: Colors.green,
            child: const Icon(Icons.upload_file),
            tooltip: 'Batch Import Sellers',
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: "add",
            onPressed: _showAddSellerDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Add Seller'),
            backgroundColor: Colors.blue,
          ),
        ],
      ),
    );
  }

  void _showAddSellerDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController codeController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController locationController = TextEditingController();
    final TextEditingController referenceController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(Icons.person_add, color: Colors.blue[700], size: 28),
                          const SizedBox(width: 12),
                          const Text('Add Seller', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Seller Name *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter seller name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Seller Code',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.tag),
                      hintText: 'e.g., SEL001',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on),
                      hintText: 'e.g., Shop 1, Market Street',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long),
                      hintText: 'Optional reference (e.g. DFS)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                      hintText: 'Optional',
                    ),
                  ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                try {
                                  final sellerName = nameController.text.trim();
                                  final nameExists = await _sellerService.sellerNameExists(sellerName);
                                  if (nameExists) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Seller name "$sellerName" is already registered'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  final passwordHash = passwordController.text.trim().isNotEmpty
                                      ? _hashPassword(passwordController.text.trim())
                                      : null;
                                  final seller = Seller(
                                    id: const Uuid().v4(),
                                    name: sellerName,
                                    code: codeController.text.trim().isEmpty ? null : codeController.text.trim(),
                                    phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                                    location: locationController.text.trim().isEmpty ? null : locationController.text.trim(),
                                    reference: referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                                    passwordHash: passwordHash,
                                    createdAt: DateTime.now(),
                                  );
                                  await _sellerService.addSeller(seller);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Seller "$sellerName" added successfully'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error adding seller: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Add Seller'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditSellerDialog(Seller seller) {
    final TextEditingController nameController = TextEditingController(text: seller.name);
    final TextEditingController codeController = TextEditingController(text: seller.code ?? '');
    final TextEditingController phoneController = TextEditingController(text: seller.phone ?? '');
    final TextEditingController locationController = TextEditingController(text: seller.location ?? '');
    final TextEditingController referenceController = TextEditingController(text: seller.reference ?? '');
    final TextEditingController passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(Icons.edit, color: Colors.blue[700], size: 28),
                          const SizedBox(width: 12),
                          const Text('Edit Seller', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Seller Name *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter seller name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Seller Code',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.tag),
                      hintText: 'e.g., SEL001',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on),
                      hintText: 'e.g., Shop 1, Market Street',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long),
                      hintText: 'Optional reference (e.g. DFS)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                      hintText: 'Leave empty to keep current password',
                      helperText: 'Enter new password to update',
                    ),
                  ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                try {
                                  final passwordHash = passwordController.text.trim().isNotEmpty
                                      ? _hashPassword(passwordController.text.trim())
                                      : seller.passwordHash;
                                  final updatedSeller = Seller(
                                    id: seller.id,
                                    name: nameController.text.trim(),
                                    code: codeController.text.trim().isEmpty ? null : codeController.text.trim(),
                                    phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                                    location: locationController.text.trim().isEmpty ? null : locationController.text.trim(),
                                    reference: referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                                    passwordHash: passwordHash,
                                    createdAt: seller.createdAt,
                                    isActive: seller.isActive,
                                  );
                                  await _sellerService.updateSeller(updatedSeller);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Seller updated successfully'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error updating seller: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Update'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showReminderDialog(Seller seller) {
    final TextEditingController messageController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Icon(Icons.notifications, color: Colors.amber[700], size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Reminders - ${seller.name}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Add new reminder',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: messageController,
                          decoration: const InputDecoration(
                            labelText: 'Reminder message',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.message),
                            hintText: 'e.g., Follow up on payment',
                          ),
                          maxLines: 2,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter a message';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_today),
                          title: const Text('Reminder date'),
                          subtitle: Text(
                            DateFormat('EEE, MMM d, y').format(selectedDate),
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[700],
                            ),
                          ),
                          trailing: TextButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() => selectedDate = picked);
                              }
                            },
                            icon: const Icon(Icons.edit_calendar, size: 20),
                            label: const Text('Change'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                try {
                                  await _reminderService.createReminder(
                                    sellerId: seller.id,
                                    message: messageController.text.trim(),
                                    reminderDate: selectedDate,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Reminder added'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add Reminder'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Your reminders',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: StreamBuilder<List<SellerReminder>>(
                      stream: _reminderService.getRemindersForSellerStream(seller.id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final reminders = snapshot.data!;
                        if (reminders.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No reminders yet',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: reminders.length,
                          itemBuilder: (context, index) {
                            final r = reminders[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: r.isCompleted
                                  ? Colors.grey.shade100
                                  : Colors.amber.shade50,
                              child: ListTile(
                                leading: Icon(
                                  r.isCompleted
                                      ? Icons.check_circle
                                      : Icons.notifications_active,
                                  color: r.isCompleted
                                      ? Colors.grey
                                      : Colors.amber.shade700,
                                  size: 28,
                                ),
                                title: Text(
                                  r.message,
                                  style: TextStyle(
                                    decoration: r.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: Text(
                                  DateFormat('MMM d, y').format(r.reminderDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!r.isCompleted)
                                      IconButton(
                                        icon: const Icon(Icons.check),
                                        onPressed: () async {
                                          await _reminderService.updateReminder(
                                            r.copyWith(isCompleted: true),
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text('Marked complete'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        },
                                        tooltip: 'Mark complete',
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () async {
                                        await _reminderService.deleteReminder(r.id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text('Reminder removed'),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                        }
                                      },
                                      tooltip: 'Delete',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteSeller(Seller seller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Delete Seller', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('Are you sure you want to delete "${seller.name}"?'),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () async {
                    try {
                      await _sellerService.deleteSeller(seller.id);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Seller deleted successfully'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error deleting seller: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBatchImportDialog() {
    final TextEditingController importController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    importController.text = 'No.,Seller Name,Phone Number,Location, Reference, Due,Credit Balance,Status,Created Date\n'
        '1,IRFAN,0321456987,JAHANIAN,DFS,500.00,0.00,Active,2026-02-19 11:17:55';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.upload_file, color: Colors.green[700], size: 28),
                          const SizedBox(width: 12),
                          const Text(
                            'Batch Import Sellers',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Enter seller data in CSV format (one per line):',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Format: No., Name, Phone, "Location, Reference, Due", Credit, Status, Date',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Combined column: Location,Reference,Due (e.g. JAHANIAN,DFS,500.00). Date: yyyy-MM-dd HH:mm:ss',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: importController,
                        decoration: const InputDecoration(
                          labelText: 'Seller Data',
                          border: OutlineInputBorder(),
                          hintText: '1,IRFAN,0321456987,JAHANIAN,DFS,500.00,0.00,Active,2026-02-19 11:17:55',
                          helperText: 'Each line represents one seller. Header row optional.',
                        ),
                        maxLines: 10,
                        minLines: 5,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter seller data';
                          }
                          final lines = value.trim().split('\n');
                          if (lines.isEmpty) {
                            return 'Please enter at least one seller';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                Navigator.pop(context);
                                await _importSellers(importController.text.trim());
                              }
                            },
                            icon: const Icon(Icons.upload),
                            label: const Text('Import'),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importSellers(String importData) async {
    try {
      final lines = importData.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No data to import'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Skip header if present (first line contains "Seller Name" etc.)
      final dataLines = lines.first.toLowerCase().contains('seller name') 
          ? lines.sublist(1) 
          : lines;

      int successCount = 0;
      int errorCount = 0;
      final errors = <String>[];

      // Show progress sheet
      showModalBottomSheet(
        context: context,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Importing ${dataLines.length} seller(s)...'),
            ],
          ),
        ),
      );

      for (int i = 0; i < dataLines.length; i++) {
        final line = dataLines[i].trim();
        if (line.isEmpty) continue;

        try {
          // Parse CSV line (handle quoted values and commas within quotes)
          final parts = _parseCsvLine(line);
          
          if (parts.isEmpty) {
            errorCount++;
            errors.add('Line ${i + 1}: Empty line');
            continue;
          }

          // Detect format: 7 cols with leading number = "No., Name, Phone, Location,Reference,Due, Credit, Status, Date"
          final bool combinedFormatWithNo = parts.length == 7 && int.tryParse(parts[0].trim()) != null;
          final bool combinedFormatNoNo = parts.length == 6 && parts.length > 2 && parts[2].contains(',');
          final bool useCombinedFormat = combinedFormatWithNo || combinedFormatNoNo;

          String sellerName;
          String phone;
          String location;
          String reference;
          double dueAmount;
          int creditIdx, statusIdx, dateIdx;

          if (useCombinedFormat) {
            if (combinedFormatWithNo) {
              sellerName = parts[1].trim();
              phone = parts.length > 2 ? parts[2].trim() : '';
              final parsed = _parseLocationReferenceDue(parts[3]);
              location = parsed.$1;
              reference = parsed.$2;
              dueAmount = parsed.$3;
              creditIdx = 4;
              statusIdx = 5;
              dateIdx = 6;
            } else {
              sellerName = parts[0].trim();
              phone = parts.length > 1 ? parts[1].trim() : '';
              final parsed = _parseLocationReferenceDue(parts[2]);
              location = parsed.$1;
              reference = parsed.$2;
              dueAmount = parsed.$3;
              creditIdx = 3;
              statusIdx = 4;
              dateIdx = 5;
            }
          } else {
            sellerName = parts[0].trim();
            phone = parts.length > 1 ? parts[1].trim() : '';
            location = parts.length > 2 ? parts[2].trim() : '';
            final bool hasReferenceColumn = parts.length > 7;
            reference = hasReferenceColumn ? parts[3].trim() : '';
            dueAmount = 0.0;
            int dueIdx = hasReferenceColumn ? 4 : 3;
            creditIdx = hasReferenceColumn ? 5 : 4;
            statusIdx = hasReferenceColumn ? 6 : 4;
            dateIdx = hasReferenceColumn ? 7 : 5;
            if (parts.length > dueIdx) {
              final dueStr = parts[dueIdx].trim();
              if (dueStr.isNotEmpty) dueAmount = double.tryParse(dueStr) ?? 0.0;
            }
            if (parts.length > creditIdx) {
              final possibleCredit = parts[creditIdx].trim();
              final parsedCredit = double.tryParse(possibleCredit);
              if (!hasReferenceColumn && (possibleCredit.isEmpty || parsedCredit != null)) {
                statusIdx = 5;
                dateIdx = 6;
              }
            }
          }

          if (sellerName.isEmpty) {
            errorCount++;
            errors.add('Line ${i + 1}: Seller name is required');
            continue;
          }

          double creditBalance = 0.0;
          if (parts.length > creditIdx) {
            final possibleCredit = parts[creditIdx].trim();
            final parsedCredit = double.tryParse(possibleCredit);
            creditBalance = parsedCredit ?? 0.0;
          }

          bool isActive = true;
          if (parts.length > statusIdx) {
            final statusStr = parts[statusIdx].trim().toLowerCase();
            isActive = statusStr != 'inactive' && statusStr != '0' && statusStr != 'no';
          }

          DateTime createdAt = DateTime.now();
          if (parts.length > dateIdx) {
            final dateStr = parts[dateIdx].trim();
            if (dateStr.isNotEmpty) {
              final isoStr = dateStr.replaceFirst(' ', 'T');
              final parsed = DateTime.tryParse(isoStr) ?? DateTime.tryParse(dateStr);
              if (parsed != null) createdAt = parsed;
            }
          }

          // Check if seller name already exists
          final nameExists = await _sellerService.sellerNameExists(sellerName);
          if (nameExists) {
            errorCount++;
            errors.add('Line ${i + 1}: Seller "$sellerName" already exists');
            continue;
          }

          // Create and add seller
          final seller = Seller(
            id: const Uuid().v4(),
            name: sellerName,
            phone: phone.isEmpty ? null : phone,
            location: location.isEmpty ? null : location,
            reference: reference.isEmpty ? null : reference,
            createdAt: createdAt,
            isActive: isActive,
          );

          await _sellerService.addSeller(seller);

          // If due amount provided, add opening-due record (reference stored in seller_history.referenceNumber)
          if (dueAmount > 0) {
            await _sellerService.addOpeningDueToSellerHistory(
              sellerId: seller.id,
              dueAmount: dueAmount,
              date: createdAt,
              referenceNumber: reference.isEmpty ? null : reference,
            );
          }

          // If credit balance provided, add to seller (shows in History as Credit Balance)
          if (creditBalance > 0) {
            await _sellerService.addCreditBalance(
              seller.id,
              creditBalance,
              description: 'Import',
            );
          }

          successCount++;

        } catch (e) {
          errorCount++;
          errors.add('Line ${i + 1}: $e');
        }
      }

      // Close progress dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Show results
      if (mounted) {
        final message = 'Import completed!\n'
            '✓ Successfully added: $successCount\n'
            '✗ Errors: $errorCount';
        
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Import Results', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message),
                      if (errors.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...errors.map((error) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $error', style: const TextStyle(fontSize: 12, color: Colors.red)),
                        )),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $successCount seller(s) successfully'),
            backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

    } catch (e) {
      if (mounted) {
        // Close progress dialog if still open
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing sellers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Parse CSV line handling quoted values
  /// Parses combined "Location, Reference, Due" (e.g. JAHANIAN,DFS,500.00).
  /// Returns (location, reference, due). If not in that format, returns (fullString, '', 0).
  (String, String, double) _parseLocationReferenceDue(String combined) {
    final s = combined.trim();
    if (s.isEmpty) return ('', '', 0.0);
    final parts = s.split(',');
    if (parts.length >= 3) {
      final last = parts.last.trim();
      final due = double.tryParse(last);
      if (due != null) {
        final reference = parts[parts.length - 2].trim();
        final location = parts.sublist(0, parts.length - 2).join(',').trim();
        return (location, reference, due);
      }
    }
    if (parts.length == 2) {
      final due = double.tryParse(parts[1].trim());
      if (due != null) return (parts[0].trim(), '', due);
    }
    if (parts.length == 1) {
      final due = double.tryParse(parts[0].trim());
      if (due != null) return ('', '', due);
    }
    return (s, '', 0.0); // whole string as location
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    String current = '';
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped quote
          current += '"';
          i++; // Skip next quote
        } else {
          // Toggle quote state
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // Field separator
        result.add(current.trim());
        current = '';
      } else {
        current += char;
      }
    }
    
    // Add last field
    result.add(current.trim());
    
    return result;
  }
}

