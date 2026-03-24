import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Web-specific initialization
  if (kIsWeb) {
    print('🌐 Initializing Flutter Web App...');

    // Add error handling for web
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      print('❌ Flutter Error: ${details.exception}');
      print('❌ Stack Trace: ${details.stack}');
    };

    // Handle platform errors
    PlatformDispatcher.instance.onError = (error, stack) {
      print('❌ Platform Error: $error');
      print('❌ Stack Trace: $stack');
      return true;
    };
  }

  runApp(MyWebApp());
}

class MyWebApp extends StatelessWidget {
  const MyWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlanetMM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: WebSplashScreen(),
      builder: (context, child) {
        // Add error boundary for web
        if (kIsWeb) {
          return ErrorBoundary(child: child ?? Container());
        }
        return child ?? Container();
      },
    );
  }
}

class WebSplashScreen extends StatefulWidget {
  const WebSplashScreen({super.key});

  @override
  _WebSplashScreenState createState() => _WebSplashScreenState();
}

class _WebSplashScreenState extends State<WebSplashScreen>
    with SingleTickerProviderStateMixin {
  late Animation<double> opacity;
  late AnimationController controller;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    print('🌐 WebSplashScreen: Initializing...');

    controller = AnimationController(
        duration: const Duration(milliseconds: 2500), vsync: this);
    opacity = Tween<double>(begin: 1.0, end: 0.0).animate(controller)
      ..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });

    // Start animation with error handling
    _startAnimation();
  }

  Future<void> _startAnimation() async {
    try {
      await controller.forward();
      if (mounted) {
        _navigateToMainPage();
      }
    } catch (e) {
      print('❌ Animation error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Animation failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _navigateToMainPage() {
    try {
      print('🌐 WebSplashScreen: Navigating to main page...');
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => WebMainPage()));
    } catch (e) {
      print('❌ Navigation error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Navigation failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorScreen();
    }

    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Center(
                  child: Opacity(
                    opacity: opacity.value,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo or app name
                        Text(
                          'PlanetMM',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Loading indicator
                        const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppTheme.brightPurple),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Loading...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Powered by Flutter Web',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMessage ?? 'Unknown error occurred',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _errorMessage = null;
                    });
                    _startAnimation();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WebMainPage extends StatefulWidget {
  const WebMainPage({super.key});

  @override
  _WebMainPageState createState() => _WebMainPageState();
}

class _WebMainPageState extends State<WebMainPage> {
  @override
  void initState() {
    super.initState();
    print('🌐 WebMainPage: Loaded successfully');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('PlanetMM'),
        backgroundColor: AppTheme.deepBlue,
        foregroundColor: AppTheme.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.shopping_cart,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            Text(
              'Welcome to PlanetMM',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.deepBlue,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Flutter Web App is working!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                print('🌐 Button pressed - App is responsive');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Test Button'),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorBoundary extends StatelessWidget {
  final Widget child;

  const ErrorBoundary({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
