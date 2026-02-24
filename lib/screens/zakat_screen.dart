import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/zakat_record.dart';
import '../services/zakat_service.dart';
import '../services/buyer_service.dart';

/// Zakat calculator: 2.5% of wealth (annual obligation for Muslims).
class ZakatScreen extends StatefulWidget {
  const ZakatScreen({super.key});

  @override
  State<ZakatScreen> createState() => _ZakatScreenState();
}

class _ZakatScreenState extends State<ZakatScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _nisabController = TextEditingController();
  final ZakatService _zakatService = ZakatService();
  final BuyerService _buyerService = BuyerService();
  static const double _zakatRate = 0.025; // 2.5%
  double? _nisab;
  bool _isLoadingProfit = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadNisab();
  }

  Future<void> _loadNisab() async {
    final nisab = await _zakatService.getNisab();
    if (mounted) {
      setState(() {
        _nisab = nisab;
        if (nisab != null && nisab > 0) {
          _nisabController.text = nisab.toStringAsFixed(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nisabController.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0;
  double get _zakatAmount => _amount * _zakatRate;
  bool get _belowNisab => _nisab != null && _nisab! > 0 && _amount > 0 && _amount < _nisab!;

  Future<void> _useProfitFromApp() async {
    setState(() => _isLoadingProfit = true);
    try {
      final profit = await _buyerService.getTotalProfitFromSalesStream().first;
      if (mounted) {
        _amountController.text = profit.toStringAsFixed(2);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profit from app: Rs. ${profit.toStringAsFixed(2)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load profit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingProfit = false);
    }
  }

  Future<void> _saveRecord() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter amount first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final record = ZakatRecord(
        id: const Uuid().v4(),
        wealthAmount: _amount,
        zakatAmount: _zakatAmount,
        date: DateTime.now(),
      );
      await _zakatService.saveRecord(record);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zakat record saved: Rs. ${_zakatAmount.toStringAsFixed(2)} on ${DateFormat('MMM d, y').format(record.date)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveNisab() async {
    final n = double.tryParse(_nisabController.text.replaceAll(',', ''));
    if (n == null || n < 0) {
      await _zakatService.setNisab(null);
      if (mounted) setState(() => _nisab = null);
    } else {
      await _zakatService.setNisab(n);
      if (mounted) setState(() => _nisab = n);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n != null && n > 0 ? 'Nisab set to Rs. ${n.toStringAsFixed(0)}' : 'Nisab cleared'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zakat (2.5%)'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Brief note
          Card(
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.green.shade800, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Zakat is 2.5% of wealth held for one lunar year (above nisab). '
                      'Enter your total amount liable for Zakat below.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Use Profit from App
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLoadingProfit ? null : _useProfitFromApp,
              icon: _isLoadingProfit
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.trending_up),
              label: Text(_isLoadingProfit ? 'Loading...' : 'Use Profit from App'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green[700],
                side: BorderSide(color: Colors.green[300]!),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Amount input
          Text(
            'Amount liable for Zakat',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: 'Rs. ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
              suffixIcon: _amountController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _amountController.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          // Nisab section
          Text(
            'Nisab threshold (Rs.) – optional',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Set minimum wealth for Zakat. Silver nisab ~595g; gold ~85g. Check current rates.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nisabController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    hintText: 'e.g. 150000',
                    prefixText: 'Rs. ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveNisab,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Nisab reminder
          if (_belowNisab)
            Card(
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.amber.shade800, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Below nisab (Rs. ${_nisab!.toStringAsFixed(0)}). Zakat may not be obligatory. Please verify with a scholar.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber.shade900,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_belowNisab) const SizedBox(height: 16),

          // Result card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.percent, color: Colors.green.shade700, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Zakat (2.5%)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _amount > 0 ? formatter.format(_zakatAmount) : 'Rs. 0.00',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  if (_amount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '2.5% of ${formatter.format(_amount)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveRecord,
                        icon: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(_isSaving ? 'Saving...' : 'Save Record'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // History
          StreamBuilder<List<ZakatRecord>>(
            stream: _zakatService.getRecordsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
              final records = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Past records',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...records.take(10).map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(Icons.history, color: Colors.green.shade700),
                      title: Text(formatter.format(r.zakatAmount)),
                      subtitle: Text(
                        '${formatter.format(r.wealthAmount)} • ${DateFormat('MMM d, y').format(r.date)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  )),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_amount > 0)
            Center(
              child: Text(
                'May Allah accept your Zakat.',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
