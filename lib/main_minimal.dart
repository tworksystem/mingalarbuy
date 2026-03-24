import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Web-specific error handling
  if (kIsWeb) {
    print('🌐 Initializing Minimal Flutter Web App...');

    // Add comprehensive error handling for web
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

  runApp(MinimalApp());
}

class MinimalApp extends StatelessWidget {
  const MinimalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeAid Commerce - Minimal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        canvasColor: Colors.white,
        primarySwatch: Colors.blue,
      ),
      home: MinimalHomePage(),
    );
  }
}

class MinimalHomePage extends StatefulWidget {
  const MinimalHomePage({super.key});

  @override
  _MinimalHomePageState createState() => _MinimalHomePageState();
}

class _MinimalHomePageState extends State<MinimalHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('HomeAid Commerce - Minimal Test'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.shopping_cart,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            Text(
              'Welcome to HomeAid Commerce',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
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
            const Text(
              'You have pushed the button this many times:',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _incrementCounter,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Increment Counter'),
            ),
            const SizedBox(height: 20),
            Text(
              'Platform: ${kIsWeb ? "Web" : "Mobile"}',
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
