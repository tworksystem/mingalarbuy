import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../app_properties.dart';

/// Modern network status banner widget
/// Matches app design with elegant yellow/amber theme
class NetworkStatusBanner extends StatelessWidget {
  final Widget child;
  final bool showWhenConnected;

  const NetworkStatusBanner({
    super.key,
    required this.child,
    this.showWhenConnected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, connectivityService, _) {
        // Show banner only when disconnected (or when connected if showWhenConnected is true)
        final shouldShow = connectivityService.isDisconnected ||
            (showWhenConnected && connectivityService.isConnected);

        if (!shouldShow) {
          return child;
        }

        return Stack(
          children: [
            child,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                offset: shouldShow ? Offset.zero : const Offset(0, -1),
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, left: 12, right: 12),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: connectivityService.isConnected
                            ? [
                                Color(0xFF4CAF50).withValues(alpha: 0.85),
                                Color(0xFF45A049).withValues(alpha: 0.85),
                              ]
                            : [
                                mediumYellow.withValues(alpha: 0.85),
                                darkYellow.withValues(alpha: 0.85),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: (connectivityService.isConnected
                                  ? Color(0xFF4CAF50)
                                  : mediumYellow)
                              .withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          spreadRadius: 0,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            connectivityService.isConnected
                                ? Icons.wifi
                                : Icons.wifi_off,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            connectivityService.isConnected
                                ? 'Connected'
                                : 'No internet connection',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Compact network status indicator (for app bar)
/// Modern design matching app theme
class NetworkStatusIndicator extends StatelessWidget {
  const NetworkStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, connectivityService, _) {
        if (connectivityService.isConnected) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                mediumYellow.withValues(alpha: 0.9),
                darkYellow.withValues(alpha: 0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: mediumYellow.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off,
                color: Colors.white,
                size: 13,
              ),
              const SizedBox(width: 5),
              Text(
                'Offline',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

