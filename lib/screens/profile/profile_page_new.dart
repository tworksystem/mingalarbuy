import 'dart:io';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/screens/auth/welcome_back_page.dart';
import 'package:ecommerce_int2/screens/settings/settings_page.dart';
import 'package:ecommerce_int2/screens/settings/about_us_page.dart';
import 'package:ecommerce_int2/screens/faq_page.dart';
import 'package:ecommerce_int2/screens/profile/my_profile_details_page.dart';
import 'package:ecommerce_int2/screens/orders/order_history_page.dart';
import 'package:ecommerce_int2/services/global_keys.dart';
import 'package:ecommerce_int2/services/app_update_service.dart';
import 'package:ecommerce_int2/services/app_download_service.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/widgets/points_dashboard_card.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProfilePageNew extends StatefulWidget {
  const ProfilePageNew({super.key});

  @override
  _ProfilePageNewState createState() => _ProfilePageNewState();
}

class _ProfilePageNewState extends State<ProfilePageNew> {
  AppUpdateInfo? _updateInfo;
  bool _isLoadingUpdate = true;
  bool _isDownloading = false;
  final AppDownloadService _downloadService = AppDownloadService();

  @override
  void initState() {
    super.initState();
    // Ensure latest billing phone/city are merged from Woo on page open
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      // Refresh user data
      await authProvider.refreshUser();
      // Load app update info
      _loadUpdateInfo();
    });
  }

  /// Load app update information from backend
  Future<void> _loadUpdateInfo() async {
    setState(() {
      _isLoadingUpdate = true;
    });

    try {
      final updateInfo =
          await AppUpdateService.getUpdateInfo(forceRefresh: true);
      if (mounted) {
        setState(() {
          _updateInfo = updateInfo;
          _isLoadingUpdate = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingUpdate = false;
        });
      }
    }
  }

  /// PROFESSIONAL FIX: Download and install app update
  /// Uses professional download service with proper error handling,
  /// Google Drive link processing, and progress tracking
  Future<void> _openUpdateLink(String url) async {
    if (_isDownloading) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download already in progress...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Check if URL is for APK download (Android) or should be opened in browser
    final isApkUrl = url.toLowerCase().contains('.apk') ||
        url.toLowerCase().contains('drive.google.com') ||
        url.toLowerCase().contains('download');

    // For Android, use download service for APK files
    if (Platform.isAndroid && isApkUrl) {
      await _downloadAndInstallUpdate(url);
    } else {
      // For other platforms or non-APK URLs, open in browser
      await _openUrlInBrowser(url);
    }
  }

  /// Download and install app update (Android)
  Future<void> _downloadAndInstallUpdate(String url) async {
    if (!mounted) return;

    setState(() {
      _isDownloading = true;
    });

    // Show download dialog with progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(
        downloadService: _downloadService,
        url: url,
        onComplete: (success, errorMessage) {
          Navigator.of(context).pop(); // Close progress dialog
          if (mounted) {
            setState(() {
              _isDownloading = false;
            });
            if (success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('App update downloaded successfully! Opening installer...'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage ?? 'Download failed. Please try again.'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'Retry',
                    textColor: Colors.white,
                    onPressed: () => _downloadAndInstallUpdate(url),
                  ),
                ),
              );
            }
          }
        },
      ),
    );
  }

  /// Open URL in browser (for non-APK URLs or non-Android platforms)
  Future<void> _openUrlInBrowser(String url) async {
    try {
      final uri = Uri.parse(url.trim());

      // Validate URL format
      if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid URL format. Please use http:// or https://'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Try to launch URL
      bool launched = false;

      // Strategy 1: External application (best for app stores)
      try {
        if (await canLaunchUrl(uri)) {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) {
            Logger.info('Successfully opened URL: $url', tag: 'ProfilePage');
            return;
          }
        }
      } catch (e) {
        Logger.warning('Failed to launch with externalApplication: $e',
            tag: 'ProfilePage');
      }

      // Strategy 2: Platform default
      if (!launched) {
        try {
          if (await canLaunchUrl(uri)) {
            launched = await launchUrl(
              uri,
              mode: LaunchMode.platformDefault,
            );
            if (launched) {
              Logger.info('Successfully opened URL with platformDefault: $url',
                  tag: 'ProfilePage');
              return;
            }
          }
        } catch (e) {
          Logger.warning('Failed to launch with platformDefault: $e',
              tag: 'ProfilePage');
        }
      }

      // Strategy 3: In-app web view
      if (!launched) {
        try {
          if (await canLaunchUrl(uri)) {
            launched = await launchUrl(
              uri,
              mode: LaunchMode.inAppWebView,
            );
            if (launched) {
              Logger.info('Successfully opened URL with inAppWebView: $url',
                  tag: 'ProfilePage');
              return;
            }
          }
        } catch (e) {
          Logger.warning('Failed to launch with inAppWebView: $e',
              tag: 'ProfilePage');
        }
      }

      // If all strategies failed
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Cannot open update link. Please check your internet connection and try again.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _openUrlInBrowser(url),
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      Logger.error('Error opening URL: $e', tag: 'ProfilePage',
          error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening update link: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Helper function to check if a custom field key should be excluded
  /// Excludes Wallet Balance, My Points, and related variations
  bool _shouldExcludeField(String key) {
    final lowerKey =
        key.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ');
    return (lowerKey.contains('wallet') && lowerKey.contains('balance')) ||
        lowerKey.contains('my point') ||
        lowerKey.contains('points balance') ||
        key == 'points_balance' ||
        key == 'my_point' ||
        key == 'my_points' ||
        key == 'My Point Value' ||
        key == 'Wallet Balance';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLoading) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
              ),
            ),
          );
        }

        if (!authProvider.isAuthenticated) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 100,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Please login to view your profile',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => WelcomeBackPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mediumYellow,
                      padding:
                          EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    ),
                    child: Text(
                      'Login',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final user = authProvider.user!;
        // User data logging removed - use Logger.debug() if needed for debugging

        return Scaffold(
          backgroundColor: Color(0xffF9F9F9),
          appBar: AppBar(
            title: Text('Profile'),
            backgroundColor: mediumYellow,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(Icons.logout),
                onPressed: () => _showLogoutDialog(context, authProvider),
              ),
            ],
          ),
          body: SafeArea(
            top: true,
            child: RefreshIndicator(
              onRefresh: () async {
                // Refresh user data
                await authProvider.refreshUser();
                // Refresh app update info
                await _loadUpdateInfo();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.only(
                      left: 16.0, right: 16.0, top: kToolbarHeight),
                  child: Column(
                    children: <Widget>[
                      CircleAvatar(
                        maxRadius: 48,
                        backgroundImage: AssetImage('assets/background.jpg'),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          // Use live user name if available, else fallback
                          (user.displayName.isNotEmpty
                                  ? user.displayName
                                  : (user.firstName.isNotEmpty
                                      ? '${user.firstName} ${user.lastName}'
                                          .trim()
                                      : user.email))
                              .trim(),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const PointsDashboardCard(),
                      // App Update Notification (if available)
                      if (!_isLoadingUpdate &&
                          _updateInfo != null &&
                          _updateInfo!.hasUpdate)
                        Container(
                          margin: EdgeInsets.only(bottom: 16.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange[400]!,
                                Colors.deepOrange[600]!,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 2,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () =>
                                  _openUpdateLink(_updateInfo!.updateLink),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.system_update,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'App Update Available',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  'NEW',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            _updateInfo!.version.isNotEmpty
                                                ? 'Version ${_updateInfo!.version} is now available'
                                                : 'A new version is available',
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.9),
                                              fontSize: 13,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Tap to update',
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.8),
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Order Management Section
                      Container(
                        margin: EdgeInsets.symmetric(vertical: 16.0),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                                bottomRight: Radius.circular(8)),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                  color: transparentYellow,
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                  offset: Offset(0, 1))
                            ]),
                        child: Column(
                          children: [
                            ListTile(
                              title: Text('My Orders'),
                              subtitle:
                                  Text('View order history and track orders'),
                              leading: Image.asset('assets/icons/package.png',
                                  width: 30, height: 30),
                              trailing: Consumer<OrderProvider>(
                                builder: (context, orderProvider, child) {
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (orderProvider.hasOrders)
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: mediumYellow,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '${orderProvider.orders.length}',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      SizedBox(width: 8),
                                      Icon(Icons.chevron_right, color: yellow),
                                    ],
                                  );
                                },
                              ),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => OrderHistoryPage())),
                            ),
                            // Divider(height: 1),
                            // ListTile(
                            //   title: const Text('My Points'),
                            //   subtitle: Consumer2<AuthProvider, PointProvider>(
                            //     builder: (context, authProvider, pointProvider, _) {
                            //       final myPoint =
                            //           authProvider.user?.customFields['my_point'];
                            //       final displayText =
                            //           (myPoint != null && myPoint.isNotEmpty)
                            //               ? '$myPoint points'
                            //               : pointProvider.formattedBalance;
                            //       return Text(
                            //         displayText,
                            //         style: const TextStyle(
                            //           color: mediumYellow,
                            //           fontWeight: FontWeight.bold,
                            //         ),
                            //       );
                            //     },
                            //   ),
                            //   leading: const Icon(Icons.stars,
                            //       color: mediumYellow, size: 30),
                            //   trailing: Consumer2<PointProvider, AuthProvider>(
                            //     builder:
                            //         (context, pointProvider, authProvider, _) {
                            //       final canExchange =
                            //           authProvider.isAuthenticated &&
                            //               authProvider.user != null &&
                            //               pointProvider.currentBalance > 0;
                            //       return Row(
                            //         mainAxisSize: MainAxisSize.min,
                            //         children: [
                            //           IconButton(
                            //             icon: const Icon(Icons.history,
                            //                 color: yellow),
                            //             tooltip: 'History',
                            //             onPressed: () =>
                            //                 Navigator.of(context).push(
                            //               MaterialPageRoute(
                            //                 builder: (_) =>
                            //                     const PointHistoryPage(),
                            //               ),
                            //             ),
                            //           ),
                            //           const SizedBox(width: 4),
                            //           OutlinedButton(
                            //             onPressed: canExchange
                            //                 ? () => _showPointExchangeDialog(
                            //                       context,
                            //                       authProvider,
                            //                       pointProvider,
                            //                     )
                            //                 : null,
                            //             style: OutlinedButton.styleFrom(
                            //               padding: const EdgeInsets.symmetric(
                            //                   horizontal: 10, vertical: 6),
                            //               side: const BorderSide(
                            //                 color: mediumYellow,
                            //                 width: 1.4,
                            //               ),
                            //               foregroundColor: mediumYellow,
                            //               textStyle: const TextStyle(
                            //                 fontSize: 12,
                            //                 fontWeight: FontWeight.w600,
                            //               ),
                            //               shape: RoundedRectangleBorder(
                            //                 borderRadius:
                            //                     BorderRadius.circular(999),
                            //               ),
                            //             ),
                            //             child: const Text('Exchange'),
                            //           ),
                            //         ],
                            //       );
                            //     },
                            //   ),
                            // ),
                            Divider(height: 1),
                            ListTile(
                              title: Text('My Profile'),
                              subtitle: Text(
                                  'View and edit your profile information'),
                              leading: Image.asset(
                                  'assets/icons/profile_icon.png',
                                  width: 30,
                                  height: 30),
                              trailing:
                                  Icon(Icons.chevron_right, color: yellow),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => MyProfileDetailsPage(),
                                  ),
                                );
                              },
                            ),
                            // Additional Information section (shows custom fields, excluding Wallet Balance and My Points)
                            if (user.customFields.isNotEmpty &&
                                user.customFields.keys.any(
                                    (key) => !_shouldExcludeField(key))) ...[
                              Divider(height: 1),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    ...user.customFields.entries
                                        .where((entry) =>
                                            !_shouldExcludeField(entry.key))
                                        .map((entry) {
                                      final filteredEntries = user
                                          .customFields.entries
                                          .where((e) =>
                                              !_shouldExcludeField(e.key))
                                          .toList();
                                      final isLast =
                                          entry == filteredEntries.last;
                                      return Column(
                                        children: [
                                          ListTile(
                                            title: Text(
                                              entry.key
                                                  .replaceAll('_', ' ')
                                                  .split(' ')
                                                  .map((word) => word.isNotEmpty
                                                      ? '${word[0].toUpperCase()}${word.substring(1)}'
                                                      : word)
                                                  .join(' '),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            subtitle: Text(
                                              entry.value.isNotEmpty
                                                  ? entry.value
                                                  : 'Not set',
                                            ),
                                            leading: Image.asset(
                                              'assets/icons/list.png',
                                              width: 30,
                                              height: 30,
                                            ),
                                          ),
                                          if (!isLast) const Divider(height: 1),
                                        ],
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                            ],
                            Divider(height: 1),
                            ListTile(
                              title: Text('Settings'),
                              subtitle: Text('Privacy and logout'),
                              leading: Image.asset(
                                'assets/icons/settings.png',
                                fit: BoxFit.scaleDown,
                                width: 30,
                                height: 30,
                              ),
                              trailing:
                                  Icon(Icons.chevron_right, color: yellow),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => SettingsPage())),
                            ),
                            Divider(height: 1),
                            ListTile(
                              title: Text('FAQ'),
                              subtitle: Text('Questions and Answer'),
                              leading: Image.asset('assets/icons/faq.png'),
                              trailing:
                                  Icon(Icons.chevron_right, color: yellow),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => FaqPage())),
                            ),
                            Divider(height: 1),
                            ListTile(
                              title: Text('About Us'),
                              subtitle: Text('Learn more about us'),
                              leading: Image.asset('assets/icons/about_us.png'),
                              trailing:
                                  Icon(Icons.chevron_right, color: yellow),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const AboutUsPage())),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logout'),
        content: Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              try {
                // Perform logout
                await authProvider.logout();

                // Navigate to login page using global navigator key for reliability
                // This ensures navigation works even if the current context is disposed
                final navigatorContext =
                    AppKeys.navigatorKey.currentContext ?? context;
                Navigator.of(navigatorContext).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => WelcomeBackPage()),
                  (route) => false,
                );
              } catch (e) {
                // Show error if logout fails
                final scaffoldContext =
                    AppKeys.scaffoldMessengerKey.currentContext ?? context;
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  SnackBar(
                    content: Text('Logout failed: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('Logout'),
          ),
        ],
      ),
    );
  }
}

/// Download Progress Dialog Widget
/// Shows download progress and handles completion
class _DownloadProgressDialog extends StatefulWidget {
  final AppDownloadService downloadService;
  final String url;
  final Function(bool success, String? errorMessage) onComplete;

  const _DownloadProgressDialog({
    required this.downloadService,
    required this.url,
    required this.onComplete,
  });

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  String _status = 'Preparing download...';
  bool _isDownloading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final filePath = await widget.downloadService.downloadAppUpdate(
        url: widget.url,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _progress = total > 0 ? received / total : 0.0;
              _status = 'Downloading... ${(_progress * 100).toStringAsFixed(1)}%';
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _errorMessage = error;
              _status = 'Download failed';
            });
            Future.delayed(const Duration(seconds: 2), () {
              widget.onComplete(false, error);
            });
          }
        },
      );

      if (filePath != null && mounted) {
        setState(() {
          _progress = 1.0;
          _status = 'Download complete! Installing...';
        });

        // Install APK on Android
        if (Platform.isAndroid) {
          final installed = await widget.downloadService.installApk(filePath);
          if (mounted) {
            if (installed) {
              setState(() {
                _isDownloading = false;
                _status = 'Installation started!';
              });
              Future.delayed(const Duration(seconds: 1), () {
                widget.onComplete(true, null);
              });
            } else {
              setState(() {
                _isDownloading = false;
                _errorMessage = 'Download complete but installation failed. Please install manually.';
                _status = 'Installation failed';
              });
              Future.delayed(const Duration(seconds: 2), () {
                widget.onComplete(false, _errorMessage);
              });
            }
          }
        } else {
          // For other platforms, just report success
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _status = 'Download complete!';
            });
            Future.delayed(const Duration(seconds: 1), () {
              widget.onComplete(true, null);
            });
          }
        }
      }
    } catch (e, stackTrace) {
      Logger.error('Error in download dialog: $e', tag: 'ProfilePage',
          error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Unexpected error: ${e.toString()}';
          _status = 'Download failed';
        });
        Future.delayed(const Duration(seconds: 2), () {
          widget.onComplete(false, _errorMessage);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDownloading, // Prevent closing during download
      child: AlertDialog(
        title: const Text('Downloading App Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isDownloading)
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
              )
            else if (_errorMessage != null)
              Icon(Icons.error, color: Colors.red, size: 48)
            else
              Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            Text(
              _status,
              style: TextStyle(
                fontSize: 14,
                color: _errorMessage != null ? Colors.red : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: [
          if (!_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }
}
