import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'models/seller.dart';
import 'providers/seller_cart_provider.dart';
import 'screens/seller_login_screen.dart';
import 'screens/seller_home_screen.dart';
import 'services/seller_auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyC1ajnBdt9UNcVH3yYAQBnCGBdH17fd6L0",
      authDomain: "noraniqaida-94425.firebaseapp.com",
      projectId: "noraniqaida-94425",
      storageBucket: "noraniqaida-94425.firebasestorage.app",
      messagingSenderId: "964648041395",
      appId: "1:964648041395:web:df093429c506acb143a9c6",
      measurementId: "G-9QJW7JKPV2",
    ),
  );
  try {
    FirebaseFirestore.instance.settings = const Settings(
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (_) {}

  runApp(const SellerApp());
}

class SellerApp extends StatelessWidget {
  const SellerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SellerCartProvider(),
      child: MaterialApp(
        title: 'ARS Traders - Seller',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        home: const SellerAuthWrapper(),
      ),
    );
  }
}

class SellerAuthWrapper extends StatefulWidget {
  const SellerAuthWrapper({super.key});

  @override
  State<SellerAuthWrapper> createState() => _SellerAuthWrapperState();
}

class _SellerAuthWrapperState extends State<SellerAuthWrapper> {
  final _authService = SellerAuthService();
  bool _isLoading = true;
  Seller? _seller;

  @override
  void initState() {
    super.initState();
    _checkStoredSeller();
  }

  Future<void> _checkStoredSeller() async {
    final seller = await _authService.getStoredSeller();
    if (mounted) {
      setState(() {
        _seller = seller;
        _isLoading = false;
      });
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
    if (_seller != null) {
      return SellerHomeScreen(seller: _seller!);
    }
    return const SellerLoginScreen();
  }
}
