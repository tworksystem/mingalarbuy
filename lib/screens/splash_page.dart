import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:ecommerce_int2/screens/auth/welcome_back_page.dart';
import 'package:ecommerce_int2/screens/main/main_page.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/widgets/modern_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late Animation<double> opacity;
  late AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
        duration: Duration(milliseconds: 2500), vsync: this);
    opacity = Tween<double>(begin: 1.0, end: 0.0).animate(controller)
      ..addListener(() {
        setState(() {});
      });
    controller.forward().then((_) {
      _checkAuthAndNavigate();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Check authentication state and navigate accordingly
  /// This ensures users stay logged in and don't get auto-logged out
  void _checkAuthAndNavigate() {
    // Wait for AuthProvider to initialize if not ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Maximum wait time: 3 seconds to prevent infinite waiting
      const maxWaitTime = Duration(seconds: 3);
      final startTime = DateTime.now();

      void checkWithTimeout() {
        final elapsed = DateTime.now().difference(startTime);

        // If still loading and haven't exceeded max wait time, wait a bit more
        if (authProvider.isLoading && elapsed < maxWaitTime) {
          Future.delayed(Duration(milliseconds: 200), () {
            if (mounted) {
              checkWithTimeout();
            }
          });
          return;
        }

        // Navigate based on authentication state (even if still loading after timeout)
        if (authProvider.isAuthenticated) {
          // User is logged in - go to main page
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => MainPage()),
            );
          }
        } else {
          // User is not logged in - go to login page
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => WelcomeBackPage()),
            );
          }
        }
      }

      checkWithTimeout();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // Use the same creative primary gradient as the rest of the app
        // so the splash experience feels fully consistent with in-app branding.
        gradient: AppTheme.primaryGradient,
      ),
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: <Widget>[
              // Main splash image - Full screen
              // PROFESSIONAL FIX: Updated to use new PLANETmm_splash_screen.jpg
              Positioned.fill(
                child: Opacity(
                  opacity: opacity.value,
                  child: Image.asset(
                    'assets/PLANETmm_splash_screen.jpg',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback if new image not found, try old splash image
                      return Image.asset(
                        'assets/planetmm_splash.jpg',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback if image not found, try GIF
                          return Image.asset(
                            'assets/planetmm-splash.gif',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) {
                              // Final fallback - try PNG
                              return Image.asset(
                                'assets/icons/planetmm_inapplogo.png',
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (context, error, stackTrace) {
                                  // Final fallback - gradient background with text
                                  return Container(
                                    decoration: const BoxDecoration(
                                  // Match main app creative gradient here as well
                                  gradient: AppTheme.primaryGradient,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(24),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.black
                                                      .withOpacity(0.35),
                                                  Colors.black.withOpacity(0.1),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withOpacity(0.18),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: const Text(
                                              'PLANETmm',
                                              style: TextStyle(
                                                fontSize: 48,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                letterSpacing: 2,
                                                fontFamily: "Montserrat",
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            'Pansy & Lincoln',
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.white,
                                              fontFamily: "Montserrat",
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'All-in-One Network Myanmar',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white70,
                                              fontFamily: "Montserrat",
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              // Loading indicator at bottom
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: opacity.value,
                    child: ModernLoadingIndicator(
                      size: 50,
                      color: AppTheme.brightPurple,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
