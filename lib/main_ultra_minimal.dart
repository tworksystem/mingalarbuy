import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

void main() {
  // Minimal initialization - no async operations
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    print('🌐 Ultra Minimal Flutter Web App Starting...');
  }

  runApp(UltraMinimalApp());
}

class UltraMinimalApp extends StatelessWidget {
  const UltraMinimalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultra Minimal Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: UltraMinimalHomePage(),
    );
  }
}

class UltraMinimalHomePage extends StatelessWidget {
  const UltraMinimalHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ultra Minimal Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 64,
              color: Colors.green,
            ),
            const SizedBox(height: 20),
            const Text(
              'Flutter Web is Working!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Platform: ${kIsWeb ? "Web" : "Mobile"}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'This is the most basic Flutter web app.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
