import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'products_screen.dart';
import 'pos_screen.dart';
import 'buyers_screen.dart';
import 'sales_history_screen.dart';
import 'sellers_screen.dart';
import 'expenses_screen.dart';
import 'borrows_screen.dart';
import 'categories_screen.dart';
import 'login_screen.dart';
import 'admin_seller_orders_screen.dart';
import 'create_manager_screen.dart';
import '../services/auth_service.dart';
import '../models/user.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final _authService = AuthService();
  UserRole? _userRole;
  String? _userName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = await _authService.getLoggedInUser();
    setState(() {
      _userRole = user?.role;
      _userName = user?.name;
      _isLoading = false;
      // If manager, set default to POS screen
      if (user?.role == UserRole.manager) {
        _selectedIndex = 2; // POS screen index
      }
    });
  }

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ProductsScreen(),
    const POSScreen(),
    const BuyersScreen(),
    const SalesHistoryScreen(),
  ];

  List<DrawerItem> get _drawerItems {
    // Managers can only see POS
    if (_userRole == UserRole.manager) {
      return [
        DrawerItem(
          icon: Icons.shopping_cart,
          title: 'POS',
          index: 2,
        ),
      ];
    }
    // Admin can see all
    return [
      DrawerItem(
        icon: Icons.dashboard,
        title: 'Dashboard',
        index: 0,
      ),
      DrawerItem(
        icon: Icons.inventory,
        title: 'Products',
        index: 1,
      ),
      DrawerItem(
        icon: Icons.shopping_cart,
        title: 'POS',
        index: 2,
      ),
      DrawerItem(
        icon: Icons.person,
        title: 'Buyer',
        index: 3,
      ),
      DrawerItem(
        icon: Icons.history,
        title: 'Sales History',
        index: 4,
      ),
    ];
  }

  void _navigateToSellers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SellersScreen(),
      ),
    );
  }

  void _showCalculatorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CalculatorDialog(),
    );
  }

  void _showWeightCalculatorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _WeightCalculatorDialog(),
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _authService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Managers can only access POS
    if (_userRole == UserRole.manager) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('POS'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.calculate_outlined),
              onPressed: () {
                _showCalculatorDialog(context);
              },
              tooltip: 'Calculator',
            ),
            IconButton(
              icon: const Icon(Icons.scale_outlined),
              onPressed: () {
                _showWeightCalculatorDialog(context);
              },
              tooltip: 'Weight Calculator',
            ),
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ],
        ),
        drawer: _buildDrawer(),
        body: const POSScreen(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_drawerItems.isNotEmpty && _selectedIndex < _drawerItems.length
            ? _drawerItems[_selectedIndex].title
            : 'Home'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            onPressed: () {
              _showCalculatorDialog(context);
            },
            tooltip: 'Calculator',
          ),
          IconButton(
            icon: const Icon(Icons.scale_outlined),
            onPressed: () {
              _showWeightCalculatorDialog(context);
            },
            tooltip: 'Weight Calculator',
          ),
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: _screens[_selectedIndex],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            constraints: const BoxConstraints(minHeight: 200),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.8),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.store,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'AR Karayana Store',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Point of Sale System',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                    if (_userName != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _userRole == UserRole.admin
                                  ? Icons.admin_panel_settings
                                  : Icons.person,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _userName!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${_userRole?.name.toUpperCase() ?? ''})',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ..._drawerItems.map((item) {
                  return _buildDrawerItem(item);
                }).toList(),
                // Admin-only features
                if (_userRole == UserRole.admin) ...[
                  // Expense button
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      leading: Icon(
                        Icons.receipt_long,
                        color: Colors.orange[700],
                        size: 24,
                      ),
                      title: const Text(
                        'Expenses',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ExpensesScreen(),
                          ),
                        );
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // Borrows button
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      leading: Icon(
                        Icons.account_balance_wallet,
                        color: Colors.amber[700],
                        size: 24,
                      ),
                      title: const Text(
                        'Borrows',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BorrowsScreen(),
                          ),
                        );
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // Manage Categories button
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      leading: Icon(
                        Icons.category,
                        color: Colors.purple[700],
                        size: 24,
                      ),
                      title: const Text(
                        'Manage Categories',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CategoriesScreen(),
                          ),
                        );
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // Manage Sellers button
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      leading: Icon(
                        Icons.people,
                        color: Colors.blue[700],
                        size: 24,
                      ),
                      title: const Text(
                        'Manage Sellers',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _navigateToSellers();
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // Seller App Orders button
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      leading: Icon(
                        Icons.phone_android,
                        color: Colors.green[700],
                        size: 24,
                      ),
                      title: const Text(
                        'Seller App Orders',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      trailing: StreamBuilder<List<dynamic>>(
                        stream: null, // We'll add a badge for pending orders count
                        builder: (context, snapshot) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green[700],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AdminSellerOrdersScreen(),
                          ),
                        );
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // Create Manager button (Admin only)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      leading: Icon(
                        Icons.person_add,
                        color: Colors.teal[700],
                        size: 24,
                      ),
                      title: const Text(
                        'Create Manager',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CreateManagerScreen(),
                          ),
                        );
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                const Divider(),
                // Logout button
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: ListTile(
                    leading: Icon(
                      Icons.logout,
                      color: Colors.red[700],
                      size: 24,
                    ),
                    title: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _handleLogout();
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '© 2024 AR Karayana Store',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(DrawerItem item) {
    final isSelected = _selectedIndex == item.index;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey[600],
          size: 24,
        ),
        title: Text(
          item.title,
          style: TextStyle(
            color: isSelected ? Theme.of(context).primaryColor : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        onTap: () {
          setState(() {
            _selectedIndex = item.index;
          });
          Navigator.pop(context);
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _refreshUserRole() async {
    await _loadUserInfo();
  }
}

class DrawerItem {
  final IconData icon;
  final String title;
  final int index;

  DrawerItem({
    required this.icon,
    required this.title,
    required this.index,
  });
}

class _CalculatorDialog extends StatefulWidget {
  const _CalculatorDialog();

  @override
  State<_CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<_CalculatorDialog> {
  String _display = '0';
  String _previousValue = '';
  String _operator = '';
  bool _shouldClearDisplay = false;

  void _onNumberPressed(String number) {
    setState(() {
      if (_shouldClearDisplay || _display == '0') {
        _display = number;
        _shouldClearDisplay = false;
      } else {
        _display += number;
      }
    });
  }

  void _onOperatorPressed(String op) {
    if (_operator.isNotEmpty && _previousValue.isNotEmpty) {
      _calculate();
    }
    setState(() {
      _previousValue = _display;
      _operator = op;
      _shouldClearDisplay = true;
    });
  }

  void _calculate() {
    if (_previousValue.isEmpty || _operator.isEmpty) return;

    final prev = double.tryParse(_previousValue) ?? 0;
    final current = double.tryParse(_display) ?? 0;
    double result = 0;

    switch (_operator) {
      case '+':
        result = prev + current;
        break;
      case '-':
        result = prev - current;
        break;
      case '×':
        result = prev * current;
        break;
      case '÷':
        result = current != 0 ? prev / current : 0;
        break;
    }

    setState(() {
      _display = result.toString();
      if (_display.endsWith('.0')) {
        _display = _display.substring(0, _display.length - 2);
      }
      _previousValue = '';
      _operator = '';
      _shouldClearDisplay = true;
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _previousValue = '';
      _operator = '';
      _shouldClearDisplay = false;
    });
  }

  void _onDecimalPressed() {
    if (!_display.contains('.')) {
      setState(() {
        _display += '.';
      });
    }
  }

  void _onPercentPressed() {
    setState(() {
      final current = double.tryParse(_display) ?? 0;
      if (_operator.isNotEmpty && _previousValue.isNotEmpty) {
        // If there's a pending operation, calculate percentage of previous value
        final prev = double.tryParse(_previousValue) ?? 0;
        final percentValue = (prev * current) / 100;
        _display = percentValue.toString();
        if (_display.endsWith('.0')) {
          _display = _display.substring(0, _display.length - 2);
        }
      } else {
        // Simple percentage (divide by 100)
        final result = current / 100;
        _display = result.toString();
        if (_display.endsWith('.0')) {
          _display = _display.substring(0, _display.length - 2);
        }
      }
    });
  }

  Widget _buildButton(String text, {Color? color, Color? textColor, VoidCallback? onPressed}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? Colors.grey[200],
            foregroundColor: textColor ?? Colors.black87,
            padding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.calculate, color: Colors.purple[700]),
                const SizedBox(width: 12),
                const Text(
                  'Calculator',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_operator.isNotEmpty)
                    Text(
                      '$_previousValue $_operator',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _display,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Buttons
            Column(
              children: [
                Row(
                  children: [
                    _buildButton('C', color: Colors.red[100], textColor: Colors.red[700], onPressed: _clear),
                    _buildButton('%', color: Colors.blue[100], textColor: Colors.blue[700], onPressed: _onPercentPressed),
                    _buildButton('÷', color: Colors.orange[100], textColor: Colors.orange[700], onPressed: () => _onOperatorPressed('÷')),
                    _buildButton('×', color: Colors.orange[100], textColor: Colors.orange[700], onPressed: () => _onOperatorPressed('×')),
                  ],
                ),
                Row(
                  children: [
                    _buildButton('7', onPressed: () => _onNumberPressed('7')),
                    _buildButton('8', onPressed: () => _onNumberPressed('8')),
                    _buildButton('9', onPressed: () => _onNumberPressed('9')),
                    _buildButton('-', color: Colors.orange[100], textColor: Colors.orange[700], onPressed: () => _onOperatorPressed('-')),
                  ],
                ),
                Row(
                  children: [
                    _buildButton('4', onPressed: () => _onNumberPressed('4')),
                    _buildButton('5', onPressed: () => _onNumberPressed('5')),
                    _buildButton('6', onPressed: () => _onNumberPressed('6')),
                    _buildButton('+', color: Colors.orange[100], textColor: Colors.orange[700], onPressed: () => _onOperatorPressed('+')),
                  ],
                ),
                Row(
                  children: [
                    _buildButton('1', onPressed: () => _onNumberPressed('1')),
                    _buildButton('2', onPressed: () => _onNumberPressed('2')),
                    _buildButton('3', onPressed: () => _onNumberPressed('3')),
                    _buildButton('=', color: Colors.green, textColor: Colors.white, onPressed: _calculate),
                  ],
                ),
                Row(
                  children: [
                    _buildButton('0', onPressed: () => _onNumberPressed('0')),
                    _buildButton('00', onPressed: () => _onNumberPressed('00')),
                    _buildButton('.', onPressed: _onDecimalPressed),
                    _buildButton('=', color: Colors.green, textColor: Colors.white, onPressed: _calculate),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightCalculatorDialog extends StatefulWidget {
  const _WeightCalculatorDialog();

  @override
  State<_WeightCalculatorDialog> createState() => _WeightCalculatorDialogState();
}

class _WeightCalculatorDialogState extends State<_WeightCalculatorDialog> {
  final TextEditingController _salePriceController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  double _calculatedWeight = 0.0;
  final List<int> _commonWeights = [50, 100, 120, 250, 500, 1000];

  @override
  void dispose() {
    _salePriceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _calculateWeight() {
    final salePrice = double.tryParse(_salePriceController.text) ?? 0;
    final amount = double.tryParse(_amountController.text) ?? 0;

    if (salePrice > 0 && amount > 0) {
      setState(() {
        // Calculate weight in grams: (amount / price_per_kg) * 1000
        _calculatedWeight = (amount / salePrice) * 1000;
      });
    } else {
      setState(() {
        _calculatedWeight = 0.0;
      });
    }
  }

  double _calculatePriceForWeight(int weightInGrams) {
    final salePrice = double.tryParse(_salePriceController.text) ?? 0;
    if (salePrice > 0) {
      return (weightInGrams / 1000) * salePrice;
    }
    return 0.0;
  }

  String _formatWeight(double grams) {
    if (grams >= 1000) {
      final kg = grams / 1000;
      return '${kg.toStringAsFixed(kg % 1 == 0 ? 0 : 2)} kg';
    }
    return '${grams.toStringAsFixed(grams % 1 == 0 ? 0 : 2)} g';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.scale, color: Colors.green[700]),
                const SizedBox(width: 12),
                const Text(
                  'Weight Calculator',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Sale Price Input
            TextField(
              controller: _salePriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Sale Price per KG *',
                hintText: 'Enter price per kg',
                prefixIcon: const Icon(Icons.currency_rupee),
                prefixText: 'Rs. ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) => _calculateWeight(),
            ),
            const SizedBox(height: 16),

            // Amount Input
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount to Spend *',
                hintText: 'Enter amount',
                prefixIcon: const Icon(Icons.attach_money),
                prefixText: 'Rs. ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) => _calculateWeight(),
            ),
            const SizedBox(height: 20),

            // Calculated Weight Result
            if (_calculatedWeight > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  children: [
                    Text(
                      'Calculated Weight',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatWeight(_calculatedWeight),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Common Weights Table
            if (_salePriceController.text.isNotEmpty &&
                double.tryParse(_salePriceController.text) != null &&
                double.parse(_salePriceController.text) > 0)
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Common Weights & Prices',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _commonWeights.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            color: Colors.grey[300],
                          ),
                          itemBuilder: (context, index) {
                            final weight = _commonWeights[index];
                            final price = _calculatePriceForWeight(weight);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue[50],
                                child: Icon(
                                  Icons.shopping_bag_outlined,
                                  color: Colors.blue[700],
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                _formatWeight(weight.toDouble()),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: Text(
                                'Rs. ${price.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

