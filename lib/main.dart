import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'providers/cart_provider.dart';
import 'providers/seller_cart_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'offline/offline_lifecycle_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preload Urdu font so it's available on Android for receipt PDF/print (ParagraphBuilder).
  try {
    final loader = FontLoader('Noto Nastaliq Urdu');
    loader.addFont(rootBundle.load('fonts/NotoNastaliqUrdu-Regular.ttf'));
    await loader.load();
    debugPrint('Urdu font (Noto Nastaliq Urdu) loaded');
  } catch (e) {
    debugPrint('Urdu font preload failed (receipts may show English fallback): $e');
  }

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
  // Larger cache = fewer repeat reads from server (helps with slowness on Blaze)
  try {
    FirebaseFirestore.instance.settings = const Settings(
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (_) {
    // Ignore if already initialized (e.g. hot reload) or unsupported on platform
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => SellerCartProvider()),
      ],
      child: OfflineLifecycleWidget(
        child: MaterialApp(
          title: 'ARS Traders - Web Admin',
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
          home: const AuthWrapper(),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final loggedIn = await _authService.isLoggedIn();
    setState(() {
      _isLoggedIn = loggedIn;
      _isLoading = false;
    });
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

    return _isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}
