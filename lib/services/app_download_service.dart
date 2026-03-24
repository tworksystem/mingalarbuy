import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';
import 'connectivity_service.dart';

/// Professional App Download Service
/// Handles APK downloads with proper error handling, Google Drive link processing,
/// and platform-specific download mechanisms
class AppDownloadService {
  static final AppDownloadService _instance = AppDownloadService._internal();
  factory AppDownloadService() => _instance;
  AppDownloadService._internal();

  final Dio _dio = Dio();
  bool _isDownloading = false;

  /// Check if currently downloading
  bool get isDownloading => _isDownloading;

  /// Download app update file
  /// Returns the downloaded file path on success, null on failure
  Future<String?> downloadAppUpdate({
    required String url,
    Function(int received, int total)? onProgress,
    Function(String error)? onError,
  }) async {
    if (_isDownloading) {
      Logger.warning('Download already in progress', tag: 'AppDownloadService');
      onError?.call('Download already in progress');
      return null;
    }

    try {
      _isDownloading = true;

      // Step 1: Check network connectivity
      final connectivityService = ConnectivityService();
      if (!connectivityService.isConnected) {
        final hasInternet =
            await connectivityService.checkInternetConnectivity();
        if (!hasInternet) {
          final error =
              'No internet connection. Please check your network and try again.';
          Logger.error(error, tag: 'AppDownloadService');
          onError?.call(error);
          return null;
        }
      }

      // Step 2: Process URL (especially for Google Drive links)
      final processedUrl = await _processDownloadUrl(url);
      if (processedUrl == null) {
        final error = 'Invalid or inaccessible download URL';
        Logger.error(error, tag: 'AppDownloadService');
        onError?.call(error);
        return null;
      }

      Logger.info('Starting download from: $processedUrl',
          tag: 'AppDownloadService');

      // Step 3: Request storage permissions (Android)
      if (!kIsWeb && Platform.isAndroid) {
        final hasPermission = await _requestStoragePermission();
        if (!hasPermission) {
          final error =
              'Storage permission is required to download the app update';
          Logger.error(error, tag: 'AppDownloadService');
          onError?.call(error);
          return null;
        }
      }

      // Step 4: Get download directory
      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null) {
        final error = 'Cannot access download directory';
        Logger.error(error, tag: 'AppDownloadService');
        onError?.call(error);
        return null;
      }

      // Step 5: Determine filename
      final fileName = _getFileNameFromUrl(processedUrl);
      final filePath = '${downloadDir.path}/$fileName';

      Logger.info('Downloading to: $filePath', tag: 'AppDownloadService');

      // Step 6: Download file with progress tracking
      await _dio.download(
        processedUrl,
        filePath,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 10),
          followRedirects: true,
          maxRedirects: 10,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total * 100).toInt();
            Logger.info(
                'Download progress: $progress% ($received/$total bytes)',
                tag: 'AppDownloadService');
            onProgress?.call(received, total);
          }
        },
      );

      // Step 7: Verify downloaded file
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();

        // Check if file is empty
        if (fileSize == 0) {
          final error = 'Downloaded file is empty';
          Logger.error(error, tag: 'AppDownloadService');
          await file.delete();
          onError?.call(error);
          return null;
        }

        // PROFESSIONAL FIX: Validate file type for APK files
        // APK files should be at least 100KB (smallest APK is usually larger)
        // If file is too small, it might be HTML (Google Drive warning page)
        if (filePath.toLowerCase().endsWith('.apk')) {
          const minApkSize = 100 * 1024; // 100KB minimum
          if (fileSize < minApkSize) {
            // Check if it's HTML content
            try {
              final content = await file.readAsString();
              if (content.contains('<html') || content.contains('<!DOCTYPE')) {
                final error =
                    'Downloaded file appears to be HTML (Google Drive warning page) instead of APK. Please check the download link.';
                Logger.error('$error File size: $fileSize bytes',
                    tag: 'AppDownloadService');
                await file.delete();
                onError?.call(
                    'Download failed: Received warning page instead of APK file. The file may be too large or require special access. Please try downloading manually from Google Drive.');
                return null;
              }
            } catch (e) {
              // If we can't read as string, it might be binary (good)
              Logger.info('File appears to be binary (good for APK)',
                  tag: 'AppDownloadService');
            }

            // Still warn if file is suspiciously small
            if (fileSize < minApkSize) {
              Logger.warning(
                  'Downloaded APK file is very small ($fileSize bytes). This might not be a valid APK.',
                  tag: 'AppDownloadService');
            }
          }
        }

        Logger.info(
            'Download completed successfully: $filePath (${fileSize} bytes)',
            tag: 'AppDownloadService');
        return filePath;
      } else {
        final error = 'Downloaded file not found';
        Logger.error(error, tag: 'AppDownloadService');
        onError?.call(error);
        return null;
      }
    } on DioException catch (e) {
      String errorMessage;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMessage =
            'Connection timeout. Please check your internet connection and try again.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage =
            'Cannot connect to server. Please check your internet connection.';
      } else if (e.response != null) {
        errorMessage =
            'Download failed: ${e.response!.statusCode} ${e.response!.statusMessage}';
      } else {
        errorMessage = 'Download failed: ${e.message ?? "Unknown error"}';
      }

      Logger.error('Download error: $errorMessage',
          tag: 'AppDownloadService', error: e);
      onError?.call(errorMessage);
      return null;
    } catch (e, stackTrace) {
      final errorMessage = 'Unexpected error during download: ${e.toString()}';
      Logger.error(errorMessage,
          tag: 'AppDownloadService', error: e, stackTrace: stackTrace);
      onError?.call(errorMessage);
      return null;
    } finally {
      _isDownloading = false;
    }
  }

  /// Process download URL - especially handles Google Drive links
  /// Google Drive requires special handling for large files (virus scan warning)
  Future<String?> _processDownloadUrl(String url) async {
    try {
      String processedUrl = url.trim();

      // Handle Google Drive links
      if (processedUrl.contains('drive.google.com')) {
        Logger.info('Processing Google Drive link: $processedUrl',
            tag: 'AppDownloadService');

        // Extract file ID from various Google Drive URL formats:
        // - https://drive.google.com/file/d/FILE_ID/view?usp=sharing (view link)
        // - https://drive.google.com/file/d/FILE_ID/view?usp=drive_link
        // - https://drive.google.com/open?id=FILE_ID
        // - https://drive.google.com/uc?export=download&id=FILE_ID (direct download)
        String? fileId;

        // Pattern 1: /file/d/FILE_ID/ (most common - works for view links)
        final fileIdMatch1 =
            RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(processedUrl);
        if (fileIdMatch1 != null) {
          fileId = fileIdMatch1.group(1);
          Logger.info('Extracted file ID from view link: $fileId',
              tag: 'AppDownloadService');
        } else {
          // Pattern 2: ?id=FILE_ID or &id=FILE_ID
          final fileIdMatch2 =
              RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(processedUrl);
          if (fileIdMatch2 != null) {
            fileId = fileIdMatch2.group(1);
            Logger.info('Extracted file ID from query parameter: $fileId',
                tag: 'AppDownloadService');
          }
        }

        if (fileId != null && fileId.isNotEmpty) {
          // PROFESSIONAL FIX: Handle Google Drive virus scan warning
          // For large files, Google Drive shows a warning page first
          // We need to extract the confirm token and use it in the download URL

          try {
            // Step 1: Try direct download first (works for small files)
            final directUrl =
                'https://drive.google.com/uc?export=download&id=$fileId';

            // Step 2: Make a GET request to check if we get the actual file or warning page
            final testResponse = await _dio.get(
              directUrl,
              options: Options(
                followRedirects: false, // Don't follow redirects yet
                validateStatus: (status) => status! < 500,
                responseType:
                    ResponseType.plain, // Get as text to check content
              ),
            );

            // Step 3: Check if response is HTML (warning page) or binary (actual file)
            final contentType =
                testResponse.headers.value('content-type') ?? '';
            final responseData = testResponse.data.toString();

            if (contentType.contains('text/html') ||
                responseData.contains('<html')) {
              // This is the warning page, extract confirm token
              Logger.info(
                  'Google Drive virus scan warning detected, extracting confirm token',
                  tag: 'AppDownloadService');

              // Extract confirm token from HTML
              // Pattern: <a href="/uc?export=download&id=FILE_ID&confirm=TOKEN"
              final confirmMatch = RegExp(
                r'/uc\?export=download[^"<>]*&confirm=([a-zA-Z0-9_-]+)',
                caseSensitive: false,
              ).firstMatch(responseData);

              if (confirmMatch != null) {
                final confirmToken = confirmMatch.group(1);
                if (confirmToken != null && confirmToken.isNotEmpty) {
                  // Use confirm token for actual download
                  final downloadUrl =
                      'https://drive.google.com/uc?export=download&id=$fileId&confirm=$confirmToken';
                  Logger.info(
                      'Google Drive download URL with confirm token: $downloadUrl',
                      tag: 'AppDownloadService');
                  return downloadUrl;
                }
              }

              // Alternative: Try to extract from form action
              final formActionMatch = RegExp(
                r'action="([^"]*uc[^"]*confirm[^"]*)"',
                caseSensitive: false,
              ).firstMatch(responseData);

              if (formActionMatch != null) {
                var actionUrl = formActionMatch.group(1);
                if (actionUrl != null) {
                  // Make it absolute URL if relative
                  if (actionUrl.startsWith('/')) {
                    actionUrl = 'https://drive.google.com$actionUrl';
                  } else if (!actionUrl.startsWith('http')) {
                    actionUrl = 'https://drive.google.com/$actionUrl';
                  }
                  Logger.info(
                      'Google Drive download URL from form action: $actionUrl',
                      tag: 'AppDownloadService');
                  return actionUrl;
                }
              }

              // If we can't extract confirm token, try alternative method
              Logger.warning(
                  'Could not extract confirm token, trying alternative method',
                  tag: 'AppDownloadService');
            } else {
              // This is the actual file, use direct URL
              Logger.info(
                  'Google Drive direct download available (no virus scan warning)',
                  tag: 'AppDownloadService');
              return directUrl;
            }
          } catch (e) {
            Logger.warning('Error processing Google Drive link: $e',
                tag: 'AppDownloadService');
            // Fall through to fallback URLs
          }

          // Fallback: Try alternative download formats
          final fallbackFormats = [
            'https://drive.google.com/uc?export=download&id=$fileId',
            'https://drive.google.com/u/0/uc?id=$fileId&export=download',
          ];

          for (final format in fallbackFormats) {
            try {
              final response = await _dio.head(
                format,
                options: Options(
                  followRedirects: true,
                  maxRedirects: 5,
                  validateStatus: (status) => status! < 500,
                ),
              );

              if (response.statusCode == 200 || response.statusCode == 302) {
                Logger.info('Google Drive fallback format works: $format',
                    tag: 'AppDownloadService');
                return format;
              }
            } catch (e) {
              continue;
            }
          }

          // Final fallback
          Logger.warning(
              'Using basic Google Drive format (may require manual confirmation)',
              tag: 'AppDownloadService');
          return 'https://drive.google.com/uc?export=download&id=$fileId';
        } else {
          Logger.warning('Could not extract file ID from Google Drive URL',
              tag: 'AppDownloadService');
          return processedUrl; // Return original URL
        }
      }

      // Validate URL format
      if (!processedUrl.startsWith('http://') &&
          !processedUrl.startsWith('https://')) {
        Logger.error('Invalid URL format: $processedUrl',
            tag: 'AppDownloadService');
        return null;
      }

      // Verify URL is accessible
      try {
        final response = await _dio.head(
          processedUrl,
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
            validateStatus: (status) => status! < 500,
          ),
        );

        if (response.statusCode == 200 || response.statusCode == 302) {
          return processedUrl;
        } else {
          Logger.warning(
              'URL returned status ${response.statusCode}: $processedUrl',
              tag: 'AppDownloadService');
          // Still return URL - might work during download
          return processedUrl;
        }
      } catch (e) {
        Logger.warning('Could not verify URL accessibility: $e',
            tag: 'AppDownloadService');
        // Still return URL - might work during download
        return processedUrl;
      }
    } catch (e, stackTrace) {
      Logger.error('Error processing download URL: $e',
          tag: 'AppDownloadService', error: e, stackTrace: stackTrace);
      return url; // Return original URL as fallback
    }
  }

  /// Request storage permission (Android)
  /// For Android 13+ (API 33+), storage permission is not needed for Downloads folder
  /// For older versions, we request permission but proceed anyway if denied
  /// (Downloads folder might still work on some devices)
  Future<bool> _requestStoragePermission() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true; // Not needed on other platforms
    }

    try {
      // Try to request storage permission (for Android < 13)
      // Note: On Android 13+, this permission doesn't exist, so it will fail gracefully
      final storageStatus = await Permission.storage.status;

      if (storageStatus.isDenied) {
        // Permission exists (Android < 13), request it
        final requestedStatus = await Permission.storage.request();
        if (requestedStatus.isGranted) {
          Logger.info('Storage permission granted', tag: 'AppDownloadService');
          return true;
        }
      } else if (storageStatus.isGranted) {
        Logger.info('Storage permission already granted',
            tag: 'AppDownloadService');
        return true;
      }

      // For Android 11+, try manage external storage as fallback
      try {
        final manageStatus = await Permission.manageExternalStorage.status;
        if (manageStatus.isDenied) {
          final requestedManageStatus =
              await Permission.manageExternalStorage.request();
          if (requestedManageStatus.isGranted) {
            Logger.info('Manage external storage permission granted',
                tag: 'AppDownloadService');
            return true;
          }
        } else if (manageStatus.isGranted) {
          return true;
        }
      } catch (e) {
        // Permission might not exist on this Android version, that's okay
        Logger.info('Manage external storage permission not available: $e',
            tag: 'AppDownloadService');
      }

      // On Android 13+, we don't need permission for Downloads folder
      // On older versions, we'll try anyway - Downloads folder might still work
      Logger.info(
          'Proceeding with download (permission may not be required on this Android version)',
          tag: 'AppDownloadService');
      return true; // Allow download attempt
    } catch (e) {
      Logger.warning('Error checking storage permission: $e',
          tag: 'AppDownloadService');
      // Return true to allow download attempt anyway
      return true;
    }
  }

  /// Get download directory
  Future<Directory?> _getDownloadDirectory() async {
    try {
      if (kIsWeb) {
        // Web doesn't support file downloads this way
        return null;
      }

      if (Platform.isAndroid) {
        // Use Downloads directory on Android
        final directory = Directory('/storage/emulated/0/Download');
        if (await directory.exists()) {
          return directory;
        }

        // Fallback to app documents directory
        final appDir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory('${appDir.path}/Downloads');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      } else if (Platform.isIOS) {
        // iOS - use app documents directory
        final appDir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory('${appDir.path}/Downloads');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      }

      // Other platforms
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    } catch (e, stackTrace) {
      Logger.error('Error getting download directory: $e',
          tag: 'AppDownloadService', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Extract filename from URL
  String _getFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final fileName = pathSegments.last;
        if (fileName.isNotEmpty && fileName.contains('.')) {
          return fileName;
        }
      }

      // Default filename for APK
      return 'app_update_${DateTime.now().millisecondsSinceEpoch}.apk';
    } catch (e) {
      Logger.warning('Error extracting filename from URL: $e',
          tag: 'AppDownloadService');
      return 'app_update_${DateTime.now().millisecondsSinceEpoch}.apk';
    }
  }

  /// Open downloaded APK file for installation (Android)
  /// Uses method channel to call native Android Intent for APK installation
  /// This is the proper way to install APKs on Android (uses FileProvider)
  Future<bool> installApk(String filePath) async {
    if (kIsWeb || !Platform.isAndroid) {
      Logger.warning('APK installation only supported on Android',
          tag: 'AppDownloadService');
      return false;
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logger.error('APK file not found: $filePath',
            tag: 'AppDownloadService');
        return false;
      }

      // Request install permission (Android 8.0+)
      final installPermissionStatus =
          await Permission.requestInstallPackages.status;
      if (installPermissionStatus.isDenied) {
        final status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          Logger.warning(
              'Install permission denied - user may need to enable "Install unknown apps" in settings',
              tag: 'AppDownloadService');
          // Continue anyway - some devices don't require this permission
        }
      }

      // Use method channel to call native Android code
      const platform = MethodChannel('com.twork.ecommerce/install_apk');

      try {
        final result = await platform.invokeMethod<bool>('installApk', {
          'filePath': filePath,
        });

        if (result == true) {
          Logger.info('APK installation launched successfully: $filePath',
              tag: 'AppDownloadService');
          return true;
        } else {
          Logger.error('APK installation failed: method returned false',
              tag: 'AppDownloadService');
          return false;
        }
      } on PlatformException catch (e) {
        Logger.error('Platform exception during APK installation: ${e.message}',
            tag: 'AppDownloadService', error: e);
        return false;
      } catch (e) {
        Logger.error('Error calling method channel: $e',
            tag: 'AppDownloadService', error: e);
        return false;
      }
    } catch (e, stackTrace) {
      Logger.error('Error installing APK: $e',
          tag: 'AppDownloadService', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Download and install app update in one go
  Future<bool> downloadAndInstall({
    required String url,
    Function(int received, int total)? onProgress,
    Function(String error)? onError,
  }) async {
    final filePath = await downloadAppUpdate(
      url: url,
      onProgress: onProgress,
      onError: onError,
    );

    if (filePath == null) {
      return false;
    }

    if (Platform.isAndroid) {
      return await installApk(filePath);
    }

    // For other platforms, just return success (file is downloaded)
    return true;
  }
}
