# Mingalarbuy - PlanetMM E-Commerce Platform

<div align="center">

**Modern Cross-Platform E-Commerce & Rewards Platform**

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-blue)](https://flutter.dev)
[![Status](https://img.shields.io/badge/Status-Production%20Ready-success)](https://github.com/mawkunnmyat/mingalarbuy)
[![GitHub](https://img.shields.io/badge/GitHub-mingalarbuy-181717?logo=github)](https://github.com/mawkunnmyat/mingalarbuy)
[![Version](https://img.shields.io/badge/Version-1.0.1%20(build%204)-blueviolet)](https://github.com/mawkunnmyat/mingalarbuy)
[![Web App](https://img.shields.io/badge/Web%20App-app.mingalarbuy.com-0ea5e9?logo=googlechrome&logoColor=white)](https://app.mingalarbuy.com)

A production-ready, enterprise-grade e-commerce application built with Flutter, seamlessly integrated with WooCommerce and WordPress. Features comprehensive loyalty rewards system, engagement hub, offline-first architecture, real-time notifications, and advanced payment solutions.

**Live Demo**: [mingalarbuy.com](https://mingalarbuy.com)

**Author**: Maw Kunn Myat | **Maintained by**: T-Work System | **Repository**: [@mawkunnmyat/mingalarbuy](https://github.com/mawkunnmyat/mingalarbuy) · Org mirror: [@tworksystem/mingalarbuy](https://github.com/tworksystem/mingalarbuy)

**Poll System (Auto-Run Poll, Engagement Hub)**  
Auto-run poll lifecycle and engagement components are maintained within this repository and documented under `docs/`.

[Features](#-features) • [Quick Start](#-getting-started) • [Architecture](#-architecture) • [Documentation](#-documentation) • [Contributing](#-contributing)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
  - [E-Commerce Core](#-e-commerce-core)
  - [Loyalty & Rewards System](#-loyalty--rewards-system)
  - [Engagement Hub](#-engagement-hub)
  - [Wallet & Payments](#-wallet--payments)
  - [User Experience](#-user-experience)
  - [Developer Experience](#-developer-experience)
- [Tech Stack](#-tech-stack)
- [Architecture](#-architecture)
- [Getting Started](#-getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Configuration](#configuration)
- [Project Structure](#-project-structure)
- [API Documentation](#-api-documentation)
- [Development](#-development)
- [Testing](#-testing)
- [Deployment](#-deployment)
- [Security](#-security)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)
- [Support](#-support)

---

## 🎯 Overview

**Mingalarbuy** (PlanetMM) is Myanmar's premier all-in-one digital network platform, bringing together lifestyle, commerce, rewards, and community into a single seamless experience. Built with Flutter for maximum cross-platform compatibility, the application delivers a native-like experience on Android, iOS, Web, and Desktop platforms.

### Project Details

- **Project Name**: Mingalarbuy / PlanetMM
- **Platform**: Cross-Platform (Android, iOS, Web, Desktop)
- **Technology Stack**: Flutter 3.0+, Dart 3.0+
- **Backend**: WordPress + WooCommerce
- **Author**: Maw Kunn Myat
- **Maintained by**: T-Work System
- **Primary Repository**: [github.com/mawkunnmyat/mingalarbuy](https://github.com/mawkunnmyat/mingalarbuy)
- **Organization Mirror**: [github.com/tworksystem/mingalarbuy](https://github.com/tworksystem/mingalarbuy)
- **License**: MIT License
- **Status**: Production Ready ✅

### Key Highlights

- 🛍️ **Full-Featured E-Commerce** - Complete shopping experience with WooCommerce integration
- 🎁 **Advanced Loyalty System** - Points earning, redemption, and transaction management
- 🎯 **Interactive Engagement Hub** - Banners, quizzes, polls, and announcements
- 📊 **Live Poll Totals** - Real-time global per-option PNP totals in the poll timer strip
- 💰 **My PNP Balance Sync** - Canonical balance reconciliation after poll win/loss with feed-aware result detection
- 🔄 **Auto-Run Poll Cadence** - Engagement provider pauses polling during result/countdown phases
- 🛡️ **WAF-Safe HTTP Client** - Honest native User-Agent, PlanetMM client headers, and Imunify360 block detection
- 🔐 **Hardened Auth & Secure Storage** - WAF-aware sign-in fallback, sparse `users/me` recovery, encrypted Android prefs
- ⚡ **SyncCoordinator** - Deduped resume / periodic sync with in-flight locks (prevents API storms)
- 🌿 **Green Performance** - Image cache RAM caps, offline queue limits, in-memory point history trim
- 🧼 **CMS HTML Sanitizer** - XSS-safe rendering for legal/about pages via whitelist stripping
- 💰 **Digital Wallet** - P2P money transfers, payment processing, and transaction history
- 📱 **Offline-First** - Full functionality without internet connection
- 🔔 **Real-Time Notifications** - Firebase Cloud Messaging with in-app notifications
- 🌐 **Multi-Platform** - Android, iOS, Web, macOS, Windows, Linux support
- 🌍 **App Subdomain Web** - Production Flutter web at `app.mingalarbuy.com` with cross-origin API to `mingalarbuy.com`
- 🖼️ **Web-Native Images** - Browser `<img>` rendering for WooCommerce media (bypasses canvas/CORS hotlink blocks)
- 📄 **CMS HTML Widget** - Shared `flutter_html` renderer with XSS sanitizer for About/Legal and engagement overlays
- 🔐 **Rewards Admin Access Control** - Per-role and per-user WordPress admin page permissions (app REST routes untouched)

---

## ✨ Features

### 🛍️ E-Commerce Core

#### Product Management
- **Product Catalog** - Browse thousands of products with rich details
- **Advanced Search** - Deep search with filters, categories, and recommendations
- **Product Details** - High-resolution images, descriptions, ratings, reviews
- **Product Variants** - Size, color, and attribute selection
- **Stock Management** - Real-time inventory tracking
- **Featured Products** - Weekly curated showcases and hero sections
- **Category Navigation** - Hierarchical category browsing
- **Product Recommendations** - AI-powered suggestions based on browsing history

#### Shopping Experience
- **Shopping Cart** - Persistent cart with offline support
- **Quantity Management** - Add, remove, and update quantities
- **Price Calculations** - Real-time totals, discounts, and taxes
- **Wishlist** - Save favorite products for later
- **Product Reviews** - User-generated reviews and ratings
- **Product Filters** - Advanced filtering by price, category, rating, availability

#### Checkout & Orders
- **Streamlined Checkout** - Multi-step checkout flow
- **Address Management** - Multiple shipping addresses with validation
- **Order Tracking** - Real-time order status updates
- **Order History** - Complete purchase history with analytics
- **Order Details** - Comprehensive order information and tracking
- **Order Confirmation** - Email and in-app confirmations
- **Order Analytics** - Dashboard with purchase insights

### 🎁 Loyalty & Rewards System

#### Points System
- **Automatic Points Earning** - Points on purchases, referrals, reviews, events
- **Points Redemption** - Redeem points for discounts and rewards
- **Transaction History** - Complete audit trail with expiration tracking
- **Points Expiration** - Configurable expiration dates and notifications
- **Offline Queue** - Points transactions queued locally, synced when online
- **WordPress Integration** - Server-side points management via custom plugin
- **Real-Time Sync** - Automatic synchronization with backend
- **Points Analytics** - Lifetime earned, redeemed, and expired tracking

#### Rewards & Exchange
- **Reward Exchange** - Exchange points for products and vouchers
- **Exchange Requests** - Request rewards with approval workflow
- **Exchange Settings** - Configurable minimum points and exchange limits
- **Prize Codes** - Redeemable prize codes and vouchers
- **Referral Program** - Earn points by referring friends
- **Transaction History** - Complete point transaction history with sorting and filtering

### 🎯 Engagement Hub

#### Interactive Features
- **Banners** - Visual announcements with images and call-to-actions
- **Quizzes** - Interactive questions with point rewards
- **Polls** - User surveys with engagement rewards
- **Announcements** - Important information displays
- **Carousel System** - Dynamic content carousel with priority-based ordering
- **Content Management** - WordPress admin interface for content creation
- **Scheduling** - Start/end date management for time-sensitive content
- **Priority System** - Content ordering and display priority

#### Auto-Run Poll System
- **Auto-Run Lifecycle** - Time-based poll cycles: voting → result display → 5-second countdown → next poll
- **Poll State API** - Lazy-evaluated state via `GET /wp-json/twork/v1/poll/state/{poll_id}`
- **Session-Scoped Votes** - Votes scoped per cycle; results by session via `GET /wp-json/twork/v1/poll/results/{poll_id}/{session_id}`
- **Live Option Totals** - Server-driven `poll_option_totals` payload with global per-option PNP stakes during open voting (no winner leak)
- **Timer Strip UX** - Horizontally scrollable, centered one-line summary (`Option 1: 120, Option 2: 85, …`) with graceful `Option totals: pending` fallback
- **Point Validation** - Pre-submit validation: selection check, total cost (base cost × selected options), balance check
- **Confirmation Flow** - Insufficient-balance dialog and spend-confirmation dialog before API submit
- **Engagement Pause** - Provider auto-poll pauses during result/countdown so the 5-second “Next poll” countdown is not interrupted
- **Cache-Aware Refresh** - Provider diff detection for `poll_option_totals` avoids unnecessary carousel rebuilds while keeping totals fresh
- **Random Winner** - Client-side random winner fallback when backend does not specify winning option

See [docs/POLL_AUTO_RUN_INTEGRATION.md](docs/POLL_AUTO_RUN_INTEGRATION.md) for integration details.

### 💰 Wallet & Payments

#### Digital Wallet
- **Wallet Balance** - Real-time balance tracking
- **Transaction History** - Complete payment and transfer history
- **Send Money** - P2P money transfers to other users
- **Request Money** - Request payments from other users
- **Quick Send** - Fast money transfer with saved contacts
- **Withdrawal** - Withdraw funds to bank accounts
- **Deposit** - Add funds to wallet via multiple methods

#### Payment Processing
- **Multiple Payment Methods** - Credit cards, digital wallets, bank transfers
- **Secure Payment Processing** - Encrypted payment data handling
- **Payment History** - Complete transaction records
- **Payment Promotions** - Discount codes and voucher support
- **Dynamic Summaries** - Real-time calculation of totals, discounts, taxes
- **Payment Security** - Secure storage with encryption

### 📱 User Experience

#### Authentication & Profile
- **User Registration** - Email/phone registration with OTP verification
- **Login System** - Secure authentication with session management
- **Password Recovery** - Forgot password with email/SMS verification
- **Profile Management** - Edit profile, avatar, preferences
- **Account Settings** - Language, country, notification preferences
- **Privacy Settings** - Control data sharing and visibility

#### Offline Support
- **Offline-First Architecture** - Full functionality without internet
- **Automatic Sync** - Background synchronization when online
- **Offline Queue** - Queue operations for later sync
- **Cache Management** - Intelligent caching with expiration
- **Network Status** - Real-time connectivity monitoring
- **Graceful Degradation** - Fallback to cached data on errors

#### Notifications
- **Push Notifications** - Firebase Cloud Messaging integration
- **In-App Notifications** - Rich notification center with actions
- **Point Notifications** - Real-time point earning/redeeming notifications with modal popups
- **Notification Settings** - Granular control over notification types
- **Background Notifications** - Notifications even when app is closed
- **Notification History** - Complete notification log
- **Badge Counters** - Unread notification indicators
- **Smart Notification Manager** - Prevents duplicate notifications and manages notification lifecycle

#### Background Services
- **WorkManager Integration** - Background order polling and sync
- **Active Sync Service** - Continuous data synchronization
- **SyncCoordinator** - Foreground dedupe + in-flight locks for resume, FCM, and fallback sync
- **Background Tasks** - Scheduled tasks for maintenance
- **Battery Optimization** - Efficient background processing, debounced app-resume work
- **App Update Service** - Dynamic app update notifications and version checking
- **App Download Service** - Seamless app update downloads and installation
- **Image Cache Management** - Global `imageCache` byte limits with memory-pressure trimming

### 🛠️ Developer Experience

#### Code Quality
- **State Management** - Provider pattern for reactive UI updates
- **Error Handling** - Comprehensive error handling with retry mechanisms
- **Logging & Monitoring** - Structured logging with multiple sinks
- **Code Analysis** - Linting, formatting, and analysis tools
- **Type Safety** - Strong typing with Dart 3.0+
- **Code Documentation** - Comprehensive inline documentation

#### Testing
- **Unit Tests** - Test individual functions and classes
- **Widget Tests** - Test UI components in isolation
- **Integration Tests** - Test complete user flows
- **Mocking** - Mocktail for dependency mocking
- **Test Coverage** - Coverage reports and analysis

#### Development Tools
- **Hot Reload** - Fast development iteration
- **Debug Tools** - Comprehensive debugging utilities
- **Performance Monitoring** - Real-time performance metrics
- **Network Logging** - HTTP request/response logging
- **Error Tracking** - Crash reporting and error analytics

---

## 🛠️ Tech Stack

### Frontend
- **Flutter** 3.0+ - Cross-platform UI framework
- **Dart** 3.0+ - Programming language
- **Provider** - State management
- **Hive** - Local database and caching
- **SharedPreferences** - Key-value storage
- **Flutter Secure Storage** - Encrypted storage

### Backend Integration
- **WooCommerce REST API** v3 - E-commerce backend
- **WordPress REST API** - Content management
- **Custom WordPress Plugins**:
  - `twork-points-system` - Points and loyalty management
  - `rewards-system` - Rewards and engagement hub
  - `fcm-notify` - Firebase Cloud Messaging integration

### Services & APIs
- **Firebase Core** - Backend services foundation
- **Firebase Cloud Messaging** - Push notifications
- **HTTP Client** - REST API communication
- **Connectivity Plus** - Network status monitoring
- **WorkManager** - Background task scheduling

### UI & UX
- **Material Design** - Google's design system
- **Cupertino Icons** - iOS-style icons
- **Google Fonts** - Custom typography
- **Cached Network Image** - Image loading and caching
- **Shimmer** - Loading placeholders
- **Flutter SVG** - Vector graphics support

### Development Tools
- **Flutter Lints** - Code analysis and linting
- **Build Runner** - Code generation
- **JSON Serializable** - JSON serialization
- **Mocktail** - Testing mocks
- **Flutter Launcher Icons** - App icon generation

---

## 🏗️ Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Application                         │
│                    (Mingalarbuy/PlanetMM)                     │
├─────────────────────────────────────────────────────────────┤
│  Presentation Layer (UI)                                      │
│  ├─ Screens (lib/screens/)                                   │
│  │  ├─ auth/          Authentication & registration           │
│  │  ├─ main/          Home & navigation                      │
│  │  ├─ product/       Product browsing & details             │
│  │  ├─ shop/          Shopping cart & checkout               │
│  │  ├─ orders/        Order management                       │
│  │  ├─ wallet/        Wallet & payments                      │
│  │  ├─ points/        Points & loyalty                       │
│  │  ├─ profile/       User profile                           │
│  │  └─ settings/      App settings                           │
│  └─ Widgets (lib/widgets/)                                   │
│     ├─ Reusable UI components                                │
│     └─ Custom widgets                                        │
├─────────────────────────────────────────────────────────────┤
│  State Management Layer (Provider)                            │
│  ├─ auth_provider.dart          Authentication state         │
│  ├─ cart_provider.dart          Shopping cart state          │
│  ├─ order_provider.dart         Order management state       │
│  ├─ point_provider.dart         Points system state         │
│  ├─ wallet_provider.dart        Wallet state                 │
│  ├─ engagement_provider.dart     Engagement hub state         │
│  └─ ... (14 providers total)                                 │
├─────────────────────────────────────────────────────────────┤
│  Business Logic Layer (Services)                              │
│  ├─ woocommerce_service.dart      WooCommerce API            │
│  ├─ auth_service.dart              Authentication            │
│  ├─ point_service.dart              Points system            │
│  ├─ payment_service.dart            Payment processing       │
│  ├─ wallet_service.dart             Wallet operations        │
│  ├─ engagement_service.dart         Engagement hub           │
│  ├─ offline_queue_service.dart      Offline sync queue       │
│  ├─ notification_service.dart       Push/local notifications │
│  ├─ connectivity_service.dart       Network monitoring       │
│  └─ ... (30+ services)                                       │
├─────────────────────────────────────────────────────────────┤
│  Data Layer                                                    │
│  ├─ Models (lib/models/)                                     │
│  │  ├─ product.dart              Product data models         │
│  │  ├─ order.dart                Order data models           │
│  │  ├─ point_transaction.dart    Points transaction models   │
│  │  └─ ... (20+ models)                                     │
│  ├─ Local Storage                                              │
│  │  ├─ Hive                      Local database              │
│  │  ├─ SharedPreferences        Key-value storage           │
│  │  └─ SecureStorage            Encrypted storage            │
│  └─ Network Layer                                             │
│     ├─ HTTP Client              REST API communication        │
│     └─ Retry Logic              Exponential backoff          │
└─────────────────────────────────────────────────────────────┘
                            ↕ REST API
┌─────────────────────────────────────────────────────────────┐
│              WordPress/WooCommerce Backend                     │
│              (mingalarbuy.com)                                 │
├─────────────────────────────────────────────────────────────┤
│  WooCommerce REST API v3                                      │
│  ├─ Products API                                             │
│  ├─ Orders API                                               │
│  ├─ Customers API                                            │
│  └─ Categories API                                           │
├─────────────────────────────────────────────────────────────┤
│  Custom WordPress Plugins                                     │
│  ├─ twork-points-system/                                     │
│  │  ├─ Points balance & transactions                         │
│  │  ├─ Points earning & redemption                          │
│  │  └─ Transaction history                                   │
│  ├─ rewards-system/                                          │
│  │  ├─ Engagement hub management                            │
│  │  ├─ Rewards & exchange                                   │
│  │  └─ Content management                                   │
│  └─ fcm-notify/                                              │
│     └─ Firebase Cloud Messaging integration                 │
└─────────────────────────────────────────────────────────────┘
```

### Design Patterns

- **Provider Pattern** - Reactive state management
- **Repository Pattern** - Data access abstraction
- **Service Layer Pattern** - Business logic separation
- **Offline-First Pattern** - Queue-based sync for offline operations
- **Retry Pattern** - Exponential backoff for network requests
- **Singleton Pattern** - Service instances management
- **Factory Pattern** - Object creation and initialization

### Key Architectural Decisions

1. **Offline-First** - All operations work offline, sync when online
2. **Service-Oriented** - Business logic separated into services
3. **Provider State Management** - Reactive UI updates
4. **Multi-Layer Caching** - Memory + persistent caching
5. **Error Resilience** - Comprehensive error handling and recovery
6. **Security First** - Encrypted storage and secure API communication

---

## 🚀 Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

- **Flutter SDK** 3.0 or higher ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Dart SDK** 3.0 or higher (included with Flutter)
- **Android Studio** or **Xcode** (for mobile development)
- **VS Code** or **Android Studio** (recommended IDEs)
- **Git** for version control
- **Node.js** 16+ (for backend webhook server, optional)
- **WordPress** installation with WooCommerce (for backend)

**Verify your setup:**
```bash
flutter doctor
```

Ensure all checks pass before proceeding.

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/mawkunnmyat/mingalarbuy.git
cd mingalarbuy
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Generate code** (if using code generation)
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

4. **Run the application**
```bash
# For connected device/emulator
flutter run

# For specific platform
flutter run -d chrome      # Web
flutter run -d macos       # macOS
flutter run -d windows     # Windows
flutter run -d linux       # Linux
```

### Configuration

#### 1. WooCommerce API Credentials

⚠️ **SECURITY WARNING**: Never commit API keys or secrets to version control!

1. Open `lib/utils/app_config.dart`
2. Update the WooCommerce API credentials:

```dart
// API Configuration (WooCommerce - mingalarbuy.com)
static const String baseUrl = 'https://mingalarbuy.com/wp-json/wc/v3';
static const String wpBaseUrl = 'https://mingalarbuy.com/wp-json/wp/v2';
static const String consumerKey = 'YOUR_CONSUMER_KEY_HERE';
static const String consumerSecret = 'YOUR_CONSUMER_SECRET_HERE';
```

**How to get WooCommerce API credentials:**
1. Login to WordPress admin panel
2. Navigate to **WooCommerce** → **Settings** → **Advanced** → **REST API**
3. Click **Add Key**
4. Set description and permissions (Read/Write)
5. Copy the Consumer Key and Consumer Secret

**Recommended Approach**: Use environment variables or secure storage:
```dart
// Option 1: Environment variables (recommended for CI/CD)
static final String consumerKey = 
    const String.fromEnvironment('CONSUMER_KEY', defaultValue: '');

// Option 2: Secure storage (recommended for runtime)
static Future<String> getConsumerKey() async {
  final secureStorage = FlutterSecureStorage();
  return await secureStorage.read(key: 'consumer_key') ?? '';
}
```

#### 2. Backend Configuration

Update the backend URL in `lib/utils/app_config.dart`:

```dart
// Backend Server Configuration (for FCM notifications)
static const String backendUrl = 'https://mingalarbuy.com';
static const String backendRegisterTokenEndpoint = 
    '/wp-json/twork/v1/register-token';
```

#### 3. Firebase Configuration (Push Notifications)

**Android Setup:**
1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com)
2. Add Android app to Firebase project
3. Download `google-services.json`
4. Place it in `android/app/google-services.json`
5. Ensure it's in `.gitignore` (already configured)

**iOS Setup:**
1. Add iOS app to Firebase project
2. Download `GoogleService-Info.plist`
3. Place it in `ios/Runner/GoogleService-Info.plist`
4. Ensure it's in `.gitignore` (already configured)

**Web Setup:**
1. Add Web app to Firebase project
2. Copy Firebase configuration
3. Update `web/index.html` with Firebase config

### Flutter Web — `app.mingalarbuy.com` Subdomain

The production web app is deployed to a **dedicated subdomain** while WooCommerce/WordPress REST APIs remain on the main domain:

| Host | Role |
| --- | --- |
| `https://app.mingalarbuy.com` | Flutter web SPA (document root `/`) |
| `https://mingalarbuy.com` | WooCommerce + WordPress REST API origin |

**Build & deploy:**
```bash
./scripts/build-web-subdomain.sh   # outputs to deploy/plesk-subdomain/
# Upload deploy/plesk-subdomain/ to Plesk subdomain httpdocs
# Include web/.htaccess.subdomain rules (SPA routing + cache headers)
```

**WordPress plugin:** activate `twork-cors` (v1.2+) — allows `app.mingalarbuy.com` CORS, uploads media headers, and referer-safe hotlink rules.

**Local Docker smoke test:**
```bash
./scripts/build-web-subdomain.sh
cd deploy/docker && docker compose up -d
open http://localhost:8080
```

#### 5. WordPress Plugin Installation

1. **Install T-Work Points System Plugin**
   - Copy `wp-content/plugins/twork-points-system/` to your WordPress installation
   - Activate the plugin through WordPress admin panel
   - The plugin will automatically create required database tables
   - Verify API endpoints are accessible at `/wp-json/twork/v1/`

2. **Install Rewards System Plugin**
   - Copy `wp-content/plugins/rewards-system/` to your WordPress installation
   - Activate the plugin through WordPress admin panel
   - Access Engagement Hub at **T-Work Rewards** → **Engagement Hub**

3. **Install FCM Notify Plugin**
   - Copy `wp-content/plugins/fcm-notify/` to your WordPress installation
   - Activate the plugin through WordPress admin panel
   - Configure Firebase service account key

4. **Install T-Work CORS Plugin** (required for Flutter Web)
   - Copy `wp-content/plugins/twork-cors/` to your WordPress installation
   - Activate — enables REST CORS for `app.mingalarbuy.com`, uploads media headers, and hotlink-safe media proxy
   - For local dev, apply `backend/nginx/twork-web-cors.conf` or run `backend/cors_proxy.js`

For detailed plugin documentation, see:
- [README_POINTS_SYSTEM.md](README_POINTS_SYSTEM.md)
- [ENGAGEMENT_HUB_DEMO_GUIDE.md](ENGAGEMENT_HUB_DEMO_GUIDE.md)

---

## 📁 Project Structure

```
mingalarbuy/
├── lib/
│   ├── main.dart                    # Application entry point
│   │
│   ├── screens/                     # UI screens organized by feature
│   │   ├── auth/                     # Authentication screens
│   │   │   ├── register_page.dart
│   │   │   ├── register_page_new.dart
│   │   │   ├── confirm_otp_page.dart
│   │   │   ├── forgot_password_page.dart
│   │   │   └── welcome_back_page.dart
│   │   ├── main/                     # Main navigation and home
│   │   │   ├── main_page.dart
│   │   │   ├── woocommerce_page.dart
│   │   │   └── components/
│   │   ├── product/                  # Product listing and details
│   │   │   ├── product_page.dart
│   │   │   ├── view_product_page.dart
│   │   │   ├── all_products_page.dart
│   │   │   ├── product_filters_page.dart
│   │   │   ├── woocommerce_product_page.dart
│   │   │   └── components/
│   │   ├── shop/                     # Shopping cart and checkout
│   │   │   ├── check_out_page.dart
│   │   │   └── components/
│   │   ├── orders/                   # Order management
│   │   │   ├── order_history_page.dart
│   │   │   ├── order_details_page.dart
│   │   │   ├── order_dashboard_page.dart
│   │   │   ├── checkout_flow_page.dart
│   │   │   ├── order_confirmation_page.dart
│   │   │   └── order_analytics_page.dart
│   │   ├── wallet/                   # Wallet and payments
│   │   │   └── wallet_page.dart
│   │   ├── points/                   # Points and loyalty
│   │   │   └── point_history_page.dart
│   │   ├── profile/                  # User profile
│   │   │   ├── profile_page_new.dart
│   │   │   ├── edit_profile_page.dart
│   │   │   └── my_profile_details_page.dart
│   │   ├── settings/                 # App settings
│   │   │   ├── settings_page.dart
│   │   │   ├── change_language_page.dart
│   │   │   ├── change_country.dart
│   │   │   ├── notifications_settings_page.dart
│   │   │   ├── cache_management_page.dart
│   │   │   ├── about_us_page.dart
│   │   │   ├── privacy_policy_page.dart
│   │   │   ├── terms_of_use_page.dart
│   │   │   └── ...
│   │   ├── address/                  # Address management
│   │   ├── payment/                  # Payment processing
│   │   ├── send_money/               # P2P money transfer
│   │   ├── request_money/            # Request money
│   │   ├── category/                 # Category browsing
│   │   ├── search/                   # Search functionality
│   │   └── notifications/            # Notifications
│   │
│   ├── services/                     # Business logic and API services
│   │   ├── woocommerce_service.dart  # WooCommerce API integration
│   │   ├── auth_service.dart         # Authentication
│   │   ├── point_service.dart         # Points system
│   │   ├── payment_service.dart       # Payment processing
│   │   ├── wallet_service.dart       # Wallet operations
│   │   ├── engagement_service.dart   # Engagement hub
│   │   ├── sync_coordinator.dart     # Foreground sync dedupe & in-flight locks
│   │   ├── secure_storage_config.dart # Centralized encrypted storage
│   │   ├── reward_exchange_service.dart # Reward exchange
│   │   ├── offline_queue_service.dart # Offline sync queue (owner-scoped, capped)
│   │   ├── notification_service.dart  # Push/local notifications
│   │   ├── push_notification_service.dart # Firebase FCM
│   │   ├── point_notification_manager.dart # Point notification management
│   │   ├── app_update_service.dart   # App update checking
│   │   ├── app_download_service.dart  # App download management
│   │   ├── connectivity_service.dart  # Network monitoring
│   │   ├── cache_service.dart        # Caching layer
│   │   ├── search_service.dart       # Search functionality
│   │   └── ... (30+ services)
│   │
│   ├── providers/                    # State management (Provider)
│   │   ├── auth_provider.dart
│   │   ├── cart_provider.dart
│   │   ├── order_provider.dart
│   │   ├── point_provider.dart
│   │   ├── wallet_provider.dart
│   │   ├── engagement_provider.dart
│   │   ├── exchange_settings_provider.dart # Exchange settings
│   │   ├── category_provider.dart
│   │   ├── product_filter_provider.dart
│   │   ├── wishlist_provider.dart
│   │   ├── review_provider.dart
│   │   ├── address_provider.dart
│   │   ├── in_app_notification_provider.dart
│   │   └── ... (15 providers)
│   │
│   ├── models/                       # Data models and DTOs
│   │   ├── product.dart
│   │   ├── order.dart
│   │   ├── point_transaction.dart
│   │   ├── auth_user.dart
│   │   ├── page_content.dart
│   │   └── ... (20+ models)
│   │
│   ├── widgets/                      # Reusable UI components
│   │   ├── product_image_widget.dart
│   │   ├── network_status_banner.dart
│   │   ├── notification_badge.dart
│   │   ├── engagement_carousel.dart
│   │   ├── cms_html_content_widget.dart  # XSS-safe CMS / engagement HTML
│   │   ├── web_html_image_widget.dart    # Browser-native <img> on Flutter web
│   │   ├── point_redemption_widget.dart
│   │   ├── point_notification_modal.dart # Point notification modal
│   │   ├── modern_loading_indicator.dart
│   │   ├── monitoring_dashboard.dart
│   │   └── ... (20+ widgets)
│   │
│   ├── utils/                        # Utilities and helpers
│   │   ├── app_config.dart           # App configuration
│   │   ├── poll_display_helpers.dart # Poll totals, labels, and timer strip formatters
│   │   ├── waf_response_utils.dart   # Imunify360 / WAF bot-protection detection
│   │   ├── cms_html_sanitizer.dart   # CMS HTML XSS stripping for legal/about pages
│   │   ├── web_image_url_utils.dart  # Safe http(s) URL validation for web <img>
│   │   ├── image_cache_config.dart   # Global imageCache RAM limits
│   │   ├── logger.dart               # Logging utilities
│   │   └── monitoring.dart           # Performance monitoring
│   │
│   └── theme/                        # App theming
│       └── app_theme.dart
│
├── test/                            # Test files
│   ├── unit/                        # Unit tests
│   ├── widget/                      # Widget tests
│   └── integration/                 # Integration tests
│
├── docs/                            # Documentation
│   └── POINTS_ARCHITECTURE.md      # Points system architecture
│
├── wp-content/                      # WordPress plugins
│   └── plugins/
│       ├── twork-points-system/    # Points system plugin
│       ├── rewards-system/         # Rewards & engagement plugin
│       │   ├── includes/class-admin-permissions.php  # WP admin page ACL
│       │   └── assets/             # Admin access-control UI (CSS/JS)
│       ├── fcm-notify/             # FCM notification plugin
│       └── twork-cors/             # Flutter web CORS + media hotlink plugin
│
├── deploy/                          # Web deployment artifacts
│   ├── docker/                     # nginx Docker smoke-test for subdomain build
│   └── plesk-subdomain/            # build output (gitignored — generated by scripts)
│
├── scripts/                         # Build & dev helpers
│   ├── build-web-subdomain.sh      # app.mingalarbuy.com Plesk build
│   ├── build-web-plesk.sh          # Shared Plesk web build pipeline
│   ├── run-web-dev.sh              # Chrome hot-reload dev server
│   └── run-web-docker.sh           # Docker static server for subdomain build
│
├── backend/                         # Backend services (optional)
│   ├── cors_proxy.js               # Local dev CORS proxy for Flutter web
│   ├── nginx/twork-web-cors.conf   # Admin nginx CORS snippet
│   └── webhook_server.js           # Webhook server for notifications
│
├── assets/                          # Images, fonts, and other assets
│   ├── icons/                       # App icons
│   └── ...
│
├── android/                         # Android-specific files
├── ios/                             # iOS-specific files
├── web/                             # Web-specific files
├── macos/                           # macOS-specific files
├── windows/                         # Windows-specific files
├── linux/                           # Linux-specific files
│
├── pubspec.yaml                     # Flutter dependencies
├── analysis_options.yaml           # Linting and analysis rules
├── LICENSE                          # License file
└── README.md                        # This file
```

---

## 📚 API Documentation

### WooCommerce REST API

The application uses WooCommerce REST API v3 for e-commerce operations.

**Base URL**: `https://mingalarbuy.com/wp-json/wc/v3`

**Authentication**: Consumer Key and Consumer Secret (Basic Auth)

#### Key Endpoints

- `GET /products` - List all products
- `GET /products/{id}` - Get product details
- `GET /orders` - List orders
- `POST /orders` - Create order
- `GET /orders/{id}` - Get order details
- `GET /customers` - List customers
- `GET /categories` - List categories

### Custom WordPress REST API

#### Points System Endpoints

- `GET /wp-json/twork/v1/points/balance/{user_id}` - Get point balance
- `GET /wp-json/twork/v1/points/transactions/{user_id}` - Get transactions (supports orderby, order, page, per_page)
- `POST /wp-json/twork/v1/points/earn` - Earn points
- `POST /wp-json/twork/v1/points/redeem` - Redeem points

#### Rewards System Endpoints

- `GET /wp-json/twork/v1/engagement/items` - Get engagement items (poll items may include `poll_option_totals` while voting is open)
- `GET /wp-json/twork/v1/rewards/exchange-requests` - Get exchange requests
- `GET /wp-json/twork/v1/rewards/exchange-settings` - Get exchange settings
- `POST /wp-json/twork/v1/rewards/exchange-request` - Create exchange request
- `GET /wp-json/twork/v1/app/update-settings` - Get app update settings

#### FCM Notification Endpoints

- `POST /wp-json/twork/v1/register-token` - Register FCM token

#### Engagement Poll Payload (`poll_option_totals`)

When a poll is in `open` or `countdown` voting status, engagement feed and update responses may include:

```json
{
  "poll_option_totals": {
    "amount_by_option": { "opt_0": 120, "opt_1": 85 },
    "vote_counts": { "opt_0": 4, "opt_1": 3 },
    "total_votes": 7,
    "total_amount": 205,
    "updated_at": "2026-05-24T10:30:00+00:00"
  }
}
```

| Field | Description |
| --- | --- |
| `amount_by_option` | Global PNP staked per option (`opt_0`, `opt_1`, … or legacy `"0"` keys) |
| `vote_counts` | Raw vote count per option (`opt_*` or legacy index keys) |
| `total_votes` | Sum of votes across options |
| `total_amount` | Sum of PNP across options |
| `updated_at` | ISO-8601 UTC timestamp of the snapshot |

> **Security:** Winner fields are intentionally omitted during open voting. Full `poll_result` data is returned only when `voting_status` is `showing_result` or `ended`.

For detailed API documentation, see:
- [README_POINTS_SYSTEM.md](README_POINTS_SYSTEM.md)
- [README_WOOCOMMERCE.md](README_WOOCOMMERCE.md)

---

## 💻 Development

### Development Team

- **Author**: Maw Kunn Myat - Original developer and architect
- **Maintained by**: T-Work System - Professional development and maintenance team

### Code Style & Standards

This project follows professional development standards and best practices:

- **Style Guide**: [Effective Dart](https://dart.dev/guides/language/effective-dart)
- **Linting**: Flutter Lints with custom analysis rules
- **Formatting**: Automatic code formatting with `dart format`
- **Documentation**: Comprehensive inline documentation and comments
- **Type Safety**: Strong typing with Dart 3.0+ null safety

**Format code:**
```bash
flutter format .
```

**Analyze code:**
```bash
flutter analyze
```

**Run both:**
```bash
flutter format . && flutter analyze
```

**Check for issues:**
```bash
flutter pub outdated  # Check for dependency updates
flutter doctor       # Verify development environment
```

### Development Workflow

#### 1. Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/mawkunnmyat/mingalarbuy.git
cd mingalarbuy

# Install dependencies
flutter pub get

# Generate code (if using code generation)
flutter pub run build_runner build --delete-conflicting-outputs

# Verify setup
flutter doctor
```

#### 2. Create a Feature Branch

```bash
# Create and switch to a new branch
git checkout -b feature/your-feature-name

# Or for bug fixes
git checkout -b fix/bug-description
```

#### 3. Make Your Changes

- Follow the existing code style and architecture
- Write comprehensive tests for new features
- Update documentation (README, inline comments, etc.)
- Follow the project's design patterns

#### 4. Run Quality Checks

```bash
# Run all tests
flutter test

# Format code
flutter format .

# Analyze code
flutter analyze

# Check for dependency updates
flutter pub outdated
```

#### 5. Commit Your Changes

Follow [Conventional Commits](https://www.conventionalcommits.org/) with a dated prefix (`DDMMYYYY`):

```bash
git add .
git commit -m "feat: 30052026 - add your feature description"
# or
git commit -m "fix: 30052026 - resolve bug description"
# or
git commit -m "docs: 30052026 - update README for new API field"
```

#### 6. Push and Create Pull Request

```bash
# Push to your fork
git push origin feature/your-feature-name

# Then create a Pull Request on GitHub
```

### Best Practices

- ✅ **Write Tests First**: Follow TDD when possible
- ✅ **Small Commits**: Make focused, atomic commits
- ✅ **Clear Messages**: Write descriptive commit messages
- ✅ **Code Review**: Request reviews from maintainers
- ✅ **Documentation**: Update docs with code changes
- ✅ **Performance**: Consider performance implications
- ✅ **Security**: Follow security best practices

### Commit Message Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/) with a **date prefix** for traceability:

```
<type>: DDMMYYYY - <imperative summary in sentence case>
```

| Type | When to use | Example |
| --- | --- | --- |
| `feat:` | New capability or user-facing enhancement | `feat: 18062026 - add app subdomain Flutter web deployment` |
| `fix:` | Bug fix or regression | `fix: 18062026 - render WooCommerce images via web-native img tags` |
| `docs:` | README, comments, or API docs only | `docs: 18062026 - document app.mingalarbuy.com deploy pipeline` |
| `refactor:` | Internal restructure, no behavior change | `refactor: 18062026 - strip forbidden XHR headers on Flutter web` |
| `perf:` | Measurable performance improvement | `perf: 18062026 - skip carousel rebuild when poll totals unchanged` |
| `test:` | Tests added or updated | `test: 18062026 - cover WebImageUrlUtils edge cases` |
| `chore:` | Tooling, deps, or maintenance | `chore: 18062026 - add Docker nginx config for web smoke tests` |
| `ci:` | CI/CD pipeline changes | `ci: 18062026 - add analyze step to GitHub Actions` |
| `style:` | Formatting only (no logic change) | `style: 18062026 - run dart format on engagement widgets` |

### Hot Reload & Hot Restart

- **Hot Reload** (`r` in terminal): Fast refresh for UI changes
- **Hot Restart** (`R` in terminal): Full app restart
- **Quit** (`q` in terminal): Stop the app

---

## 🧪 Testing

### Running Tests

```bash
# Run all tests
flutter test

# Run tests with coverage
flutter test --coverage

# Run specific test file
flutter test test/services/auth_service_test.dart

# Run tests in watch mode
flutter test --watch
```

### Test Structure

- **Unit Tests**: Test individual functions and classes
- **Widget Tests**: Test UI components in isolation
- **Integration Tests**: Test complete user flows

### Writing Tests

Example unit test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  group('PointService', () {
    test('should calculate points correctly', () {
      // Test implementation
    });
  });
}
```

---

## 🚢 Deployment

### Building for Production

**Android:**
```bash
flutter build apk --release          # APK
flutter build appbundle --release    # App Bundle (Play Store)
```

**iOS:**
```bash
flutter build ios --release
# Then archive and upload via Xcode
```

**Web:**
```bash
# Production subdomain (app.mingalarbuy.com — API stays on mingalarbuy.com)
./scripts/build-web-subdomain.sh

# Local dev with hot reload (Chrome)
./scripts/run-web-dev.sh

# Serve built subdomain bundle via Docker (http://localhost:8080)
./scripts/build-web-subdomain.sh && ./scripts/run-web-docker.sh

# Generic release build
flutter build web --release
```

**Desktop:**
```bash
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

### Environment-Specific Builds

For different environments (dev, staging, production), use build flavors:

```bash
# Android flavors
flutter build apk --flavor production --release

# iOS schemes
flutter build ios --release --flavor production
```

### Pre-Deployment Checklist

- [ ] Update version in `pubspec.yaml`
- [ ] Update `CHANGELOG.md` (if maintained)
- [ ] Run all tests: `flutter test`
- [ ] Run analysis: `flutter analyze`
- [ ] Test on physical devices (iOS and Android)
- [ ] Verify API endpoints and credentials
- [ ] Test offline functionality
- [ ] Verify push notifications
- [ ] Check app icons and splash screens
- [ ] Review app permissions
- [ ] Test payment flows
- [ ] Verify points system integration
- [ ] Test engagement hub features
- [ ] Performance testing
- [ ] Security audit

---

## 🔒 Security

### Best Practices

1. **Never Commit Secrets**
   - API keys, passwords, and tokens should never be in version control
   - Use environment variables or secure storage
   - The repository has been cleaned of any previously committed secrets

2. **Secure Storage**
   - Use `flutter_secure_storage` for sensitive data via `SecureStorageConfig` (encrypted shared preferences on Android)
   - Encrypt data at rest when possible
   - Use HTTPS for all API communications

3. **WAF & Bot Protection (Imunify360)**
   - Use honest native `User-Agent` strings — do not spoof browser fingerprints
   - Send `X-PlanetMM-Client` headers for hosting allow-list rules
   - Detect WAF block payloads via `WafResponseUtils` (HTTP 200 + JSON `message`)
   - Auth sign-in falls back to `POST /wp-json/twork/v1/auth/sign-in` when `/users/me` is blocked

4. **CMS Content Safety**
   - Sanitize WordPress HTML via `CmsHtmlSanitizer` before `flutter_html` render
   - Strip `<script>`, event handlers, `javascript:` URLs, and dangerous embeds
   - Preserve allowed markup for legal, privacy, and about pages

5. **API Security**
   - Validate all user inputs
   - Use HTTPS only
   - Implement proper authentication and authorization
   - Rate limiting on backend

6. **Code Obfuscation** (Optional)
   ```bash
   flutter build apk --release --obfuscate --split-debug-info=./debug-info
   ```

### Security Checklist

- [ ] All API keys stored securely (not in code)
- [ ] HTTPS enforced for all network requests
- [ ] User data encrypted at rest
- [ ] Authentication tokens stored securely
- [ ] Input validation on all user inputs
- [ ] Error messages don't expose sensitive information
- [ ] Dependencies are up to date (check `flutter pub outdated`)
- [ ] Regular security audits
- [ ] Penetration testing

---

## 🐛 Troubleshooting

### Common Issues

#### 1. Build Errors

**Problem**: `flutter pub get` fails
```bash
# Solution: Clean and reinstall
flutter clean
flutter pub get
```

**Problem**: iOS build fails
```bash
# Solution: Update pods
cd ios
pod deintegrate
pod install
cd ..
```

#### 2. API Connection Issues

- Verify WooCommerce API credentials in `app_config.dart`
- Check network connectivity
- Verify backend URL is correct
- Check CORS settings (for web)
- Verify SSL certificate is valid

#### 3. Offline Queue Not Syncing

- Check connectivity service is running
- Verify offline queue service is initialized
- Check logs for sync errors
- Ensure backend endpoints are accessible
- Verify authentication tokens are valid

#### 4. Push Notifications Not Working

- Verify Firebase configuration files are present
- Check device token registration
- Verify backend webhook server is running (if applicable)
- Check notification permissions
- Verify FCM service account key is configured

#### 5. Points Not Updating

- Verify WordPress plugin is activated
- Check API authentication
- Review point service logs
- Verify database tables exist
- Check offline queue for pending transactions

#### 6. WAF / Sign-In Blocked on Release APK

- Confirm hosting allow-list includes `X-PlanetMM-Client: 1` header
- Check Imunify360 bot-protection logs for blocked IPs
- Verify `POST /wp-json/twork/v1/auth/sign-in` endpoint is reachable
- Ensure app uses honest native User-Agent (not spoofed Chrome)
- Review `auth_service.dart` logs for `waf_blocked` error flag

#### 8. App Feels Slow After Long Poll Sessions

- Home balance polling runs every 12s (not 2s) — expected during active polls
- Check `SyncCoordinator` logs for dedupe skips (normal, not errors)
- Image cache trims automatically on memory pressure
- Point history shows max 300 rows in RAM — use date filter for older entries

#### 9. Engagement Hub Not Loading

- Verify WordPress plugin is activated
- Check API endpoints are accessible
- Review engagement service logs
- Verify content is published and active
- Check date range for scheduled content

### Getting Help

1. Check existing [Issues](https://github.com/mawkunnmyat/mingalarbuy/issues) or [Org mirror issues](https://github.com/tworksystem/mingalarbuy/issues)
2. Review documentation in `docs/` folder
3. Check [Flutter documentation](https://flutter.dev/docs)
4. Contact support: support@tworksystem.com

---

## 🤝 Contributing

We welcome contributions from the community! This project is maintained by T-Work System and was originally developed by Maw Kunn Myat. We appreciate any help in making this project better.

### How to Contribute

#### Contribution Process

1. **Fork the repository**
   ```bash
   # Click the "Fork" button on GitHub, or use:
   gh repo fork mawkunnmyat/mingalarbuy
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/amazing-feature
   # or
   git checkout -b fix/bug-description
   ```

3. **Make your changes**
   - Follow the existing code style and conventions
   - Write or update tests for new features
   - Update documentation as needed
   - Ensure all existing tests pass

4. **Commit your changes** (follow [Conventional Commits](https://www.conventionalcommits.org/))
   ```bash
   git commit -m "feat: add amazing feature description"
   # or
   git commit -m "fix: resolve bug description"
   ```

5. **Push to your branch**
   ```bash
   git push origin feature/amazing-feature
   ```

6. **Open a Pull Request**
   - Provide a clear and detailed description
   - Reference related issues (e.g., "Fixes #123")
   - Add screenshots for UI changes
   - Ensure CI checks pass

### Pull Request Guidelines

- ✅ **Clear Description**: Explain what changes you made and why
- ✅ **Reference Issues**: Link to related issues using keywords (fixes, closes, resolves)
- ✅ **Test Coverage**: Ensure all tests pass and add tests for new features
- ✅ **Documentation**: Update relevant documentation files
- ✅ **Code Quality**: Follow Flutter/Dart style guidelines
- ✅ **Focused Scope**: Keep PRs focused on a single feature or fix
- ✅ **Screenshots**: Add screenshots for UI/UX changes

### Code Review Process

All pull requests require review before merging. Our maintainers will review:

- **Code Quality**: Adherence to Flutter/Dart best practices
- **Test Coverage**: Adequate test coverage for new features
- **Documentation**: Updated documentation and comments
- **Security**: Security considerations and best practices
- **Performance**: Performance impact and optimization opportunities
- **Architecture**: Alignment with project architecture and patterns

### Development Standards

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines
- Use meaningful variable and function names
- Add comments for complex logic
- Write self-documenting code
- Maintain test coverage above 80%
- Follow the existing code structure and patterns

### Getting Help

If you need help with contributing:
- Check existing [Issues](https://github.com/mawkunnmyat/mingalarbuy/issues)
- Review the [Documentation](#-documentation) section
- Contact: support@tworksystem.com

**Thank you for contributing to Mingalarbuy!** 🙏

---

## 📄 License

Copyright (c) 2025 T-Work System / Mingalarbuy

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

### Copyright Notice

- **Copyright (c) 2025 T-Work System. All rights reserved.**
- **Author**: Maw Kunn Myat
- **Maintained by**: T-Work System

This software is provided under the MIT License, which permits use, modification, and distribution subject to the terms and conditions specified in the LICENSE file. The copyright notice and permission notice must be included in all copies or substantial portions of the software.

### License Terms

**MIT License** - A permissive license that allows you to:
- ✅ Use commercially
- ✅ Modify
- ✅ Distribute
- ✅ Sublicense
- ✅ Private use

**Requirements**:
- Include license and copyright notice
- State changes (if you modify the code)

**Limitations**:
- ❌ No liability
- ❌ No warranty

**Note**: Assets, fonts, and other third-party resources may have separate licenses. Please check individual file headers and respect their respective licensing terms.

---

## 📞 Support & Contact

### Getting Help

We're here to help! Here are the best ways to get support:

#### Documentation
- **Project Documentation**: Check `docs/` folder for detailed guides
- **API Documentation**: See [API Documentation](#-api-documentation) section
- **Plugin Documentation**: 
  - [Points System](README_POINTS_SYSTEM.md)
  - [WooCommerce Integration](README_WOOCOMMERCE.md)

#### Community Support
- **GitHub Issues**: [Report bugs or request features](https://github.com/mawkunnmyat/mingalarbuy/issues)
- **Org Mirror Issues**: [tworksystem/mingalarbuy/issues](https://github.com/tworksystem/mingalarbuy/issues)
- **GitHub Discussions**: [Ask questions and share ideas](https://github.com/mawkunnmyat/mingalarbuy/discussions)

#### Direct Contact
- **Email**: support@tworksystem.com
- **Website**: [www.tworksystem.com](https://www.tworksystem.com)
- **Store**: [mingalarbuy.com](https://mingalarbuy.com)

#### Project Information
- **Author**: Maw Kunn Myat
- **Maintained by**: T-Work System
- **Primary Repository**: [github.com/mawkunnmyat/mingalarbuy](https://github.com/mawkunnmyat/mingalarbuy)
- **Organization Mirror**: [github.com/tworksystem/mingalarbuy](https://github.com/tworksystem/mingalarbuy)

---

## 🙏 Acknowledgments

We would like to express our gratitude to the following technologies, platforms, and individuals:

### Technologies & Platforms
- [Flutter](https://flutter.dev) - Modern cross-platform UI framework
- [Dart](https://dart.dev) - Type-safe programming language
- [WooCommerce](https://woocommerce.com) - Powerful e-commerce platform
- [WordPress](https://wordpress.org) - Flexible CMS and backend
- [Firebase](https://firebase.google.com) - Comprehensive backend services
- [Provider](https://pub.dev/packages/provider) - State management solution

### Team & Contributors
- **Maw Kunn Myat** — Original author and platform architect
- **T-Work System** — Development team and maintainers
- **Mapoee Phyu** — Performance, sync, and release engineering (mapoeeiphyu2017.miitinternship@gmail.com)
- All contributors who have helped improve this project
- The open-source community for their invaluable tools and libraries

---

## 📊 Project Status

**Current Version**: 1.0.1 (build 4)

**Status**: ✅ Production Ready

**Last Updated**: 18 June 2026

**Author**: Maw Kunn Myat

**Maintained by**: T-Work System

**Contributors**: Mapoee Phyu (mapoeeiphyu2017.miitinternship@gmail.com)

### Recent Updates (18 June 2026 — Flutter Web Subdomain & Media)

#### 🌍 App Subdomain Deployment (`app.mingalarbuy.com`)
- ✅ **Cross-origin API routing** — `AppConfig` resolves `app.mingalarbuy.com` UI to `mingalarbuy.com` WooCommerce/WordPress API
- ✅ **Forbidden header stripping** — Removes `User-Agent`, `Referer`, `Host` from Dio requests on web (browser blocks them)
- ✅ **Plesk build pipeline** — `build-web-subdomain.sh` with `BASE_HREF=/`, SPA `.htaccess`, and deploy zip
- ✅ **Docker smoke test** — `deploy/docker/` nginx serves subdomain build at `localhost:8080`
- ✅ **Dev scripts** — `run-web-dev.sh` (hot reload) and `run-web-docker.sh` (static preview)

#### 🖼️ Web-Native Image Rendering
- ✅ **`WebHtmlImageWidget`** — Renders WooCommerce media via browser `<img>` (avoids canvas taint / hotlink 403)
- ✅ **`WebImageUrlUtils`** — Validates http(s) URLs and escapes HTML attributes before DOM injection
- ✅ **Product & category screens** — Unified web image path across catalog, search, notifications, and product detail
- ✅ **`CmsHtmlContentWidget`** — Shared `flutter_html` renderer with light/dark schemes for About and engagement overlays

#### 🛡️ T-Work CORS Plugin v1.2
- ✅ **`app.mingalarbuy.com` origin** — Added to allowed CORS and hotlink referer patterns
- ✅ **Uploads media headers** — CORS + cache headers on `wp-content/uploads` via `.htaccess` injection
- ✅ **Media proxy REST route** — Serves hotlink-blocked images through WordPress when referer is allowed
- ✅ **PlanetMM client headers** — `X-PlanetMM-*` allowed in preflight `Access-Control-Allow-Headers`

#### 🔐 Rewards Admin Access Control (WordPress)
- ✅ **`Rewards_Admin_Permissions`** — Central module for per-page admin ACL (Transactions, Engagement, Users, Settings, etc.)
- ✅ **Role + user overrides** — Grant or deny individual screens by WordPress role or specific user account
- ✅ **Strict mode toggle** — Optional enforcement that supersedes legacy `manage_woocommerce` blanket access
- ✅ **Access Control screen** — Super-admin settings UI with Select2 user search, unsaved-change guard, and role matrix
- ✅ **Action gates** — `rewards_require_action()` replaces scattered capability checks on POST/AJAX handlers
- ✅ **App API untouched** — Mobile/web REST routes and `twork_*` storage remain unchanged; admin-only hardening

### Recent Updates (07 June 2026 — Plugin Directory Migration)

#### 📦 WordPress Plugin Layout
- ✅ **`fcm-notify/`** — FCM plugin relocated from `twork-fcm-notify/` with updated README and CONTRIBUTING guide
- ✅ **`rewards-system/`** — Rewards plugin relocated from `twork-rewards-system/`; bootstrap aligned to `rewards-system.php`
- ✅ **`fcm-notify.php` / `rewards-system.php`** — Plugin entry files renamed to match folder names for cleaner wp-admin activation paths
- ✅ **Branding cleanup** — Plugin headers and log prefixes normalized; no functional REST route changes
- ✅ **Security** — `serviceAccountKey.json` remains gitignored; nested plugin `.git` repos removed from monorepo tree

### Recent Updates (30 May 2026 — Poll Actual Result)

#### 📊 Poll Loss & Transaction History
- ✅ **`poll_bet_result` FCM** — Loss-path notification nudges app to refresh cache without balance change
- ✅ **Background poll tick** — Fetches `/poll/results` and patches disk cache while app is backgrounded
- ✅ **Resume reconcile** — Hydrates disk cache first, then syncs missed poll rounds on app resume
- ✅ **Actual Result UI** — Point history shows prominent winning option label for poll bets
- ✅ **API fallback** — Rewards plugin derives `winning_option` when meta backfill has not run yet
- ✅ **Point ledger admin** — Trash/archive workflow for `twork_point_transactions` (balance SUM unchanged)

### Recent Updates (30 May 2026 — Performance & Reliability)

#### ⚡ SyncCoordinator & App Lifecycle
- ✅ **SyncCoordinator** — Dedupe intervals + in-flight locks prevent overlapping resume, FCM, and fallback sync storms
- ✅ **Resume debounce** — 3-second guard skips duplicate heavy work when app resumes rapidly
- ✅ **Session reset** — Coordinator keys cleared on login/logout/account switch
- ✅ **Engagement poll guard** — Periodic feed poll respects coordinator before hitting the network

#### 🌿 Green Performance & Memory
- ✅ **Image cache caps** — 50 images / ~80MB decoded RAM budget via `AppImageCacheConfig`
- ✅ **Memory pressure trim** — Clears `imageCache` on `didHaveMemoryPressure` to keep app alive
- ✅ **Offline queue cap** — Max 100 persisted items; oldest dropped on overflow
- ✅ **Owner-scoped queue** — `owner_user_id` stamped on queue items; stale rows dropped on account switch
- ✅ **Point history RAM cap** — 300 newest transactions in memory with Burmese snackbar notice
- ✅ **Home balance polling** — Interval relaxed from 2s → 12s to cut rebuild churn during poll sessions

#### 🎯 Poll UX & Accessibility
- ✅ **Auto-run rollover shell** — "Next round starting…" transition when stale `hasInteracted` persists across sessions
- ✅ **No voting UI flash** — Suppress vote receipt after result window ends until feed refreshes
- ✅ **Semantics labels** — Screen reader support on poll options, submit, and countdown UI

#### 🧼 CMS & Backend Admin
- ✅ **CmsHtmlSanitizer** — Whitelist-style stripping before `flutter_html` (scripts, handlers, `javascript:` URLs)
- ✅ **Point ledger trash workflow** — Soft-delete, restore, bulk actions, and archive purge in rewards admin (balance SUM unchanged)

### Recent Updates (30 May 2026 — Security Hardening)

#### 🛡️ WAF Hardening & HTTP Client Identity
- ✅ **Honest native User-Agent** — Replaced fake Chrome UA with `PlanetMM/{version} (Platform; build; Flutter)` to avoid TLS fingerprint mismatches
- ✅ **PlanetMM client headers** — `X-PlanetMM-Client`, `X-PlanetMM-Version`, `X-PlanetMM-Build`, `X-PlanetMM-Platform` for Imunify360 allow-list rules
- ✅ **WafResponseUtils** — Detects Imunify360 / bot-protection JSON bodies even on HTTP 200 responses
- ✅ **ApiService interceptor** — Tags WAF-blocked responses in `response.extra` for downstream services
- ✅ **Engagement service** — Surfaces user-facing WAF error message instead of silent empty feeds

#### 🔐 Authentication & Secure Storage
- ✅ **WAF-aware sign-in fallback** — `POST /twork/v1/auth/sign-in` when `/users/me` returns bot-protection payload
- ✅ **Sparse users/me recovery** — Merges WooCommerce customer + stored identity when WordPress profile is incomplete
- ✅ **SecureStorageConfig** — Centralized `FlutterSecureStorage` with `encryptedSharedPreferences` for Android release builds
- ✅ **profileDisplayLabel** — Resilient profile header label when name/email fields are empty after WAF throttling
- ✅ **Removed WooCommerce credential query params** — Wallet/points endpoints rely on authenticated REST headers only

#### 🎯 Engagement Hub & Poll UX
- ✅ **Stale-while-revalidate carousel** — Poll UI stays visible while feed refreshes (no full-screen spinner on every poll tick)
- ✅ **Live field cache hygiene** — Disk cache strips poll timer/schedule; only vote preferences persist offline
- ✅ **Server end-time guard** — Result transition burst fires only when server `ends_at` is known
- ✅ **Auto-run poll resolution (backend)** — Session-scoped winner lookup for transaction history labels

#### 🧹 Feature Cleanup
- ✅ **Spin Wheel removed** — Mobile spin wheel provider, service, and home UI retired
- ✅ **Lucky Box removed** — Lucky box banner, request sheet, and backend admin module retired
- ✅ **Point history cleanup** — Lucky Box transaction filter and labels removed

### Recent Updates (25 May 2026)

#### Poll Balance & My PNP Reconciliation
- ✅ **Feed-aware result phase** - `PollWinnerPopupService` reconciles balance when the engagement feed already shows `showing_result` / winner data, even if `/poll/state` still reports ACTIVE (auto-run polls)
- ✅ **Queued PNP sync** - Bounded reconcile-key cache with coalesced pending sync to prevent duplicate balance pulls per poll round
- ✅ **Win + loss reconcile** - Session-scoped balance sync for both winning and losing outcomes after countdown
- ✅ **My PNP debug tracing** - Structured `MyPnpBalanceDebug` console helpers for balance apply/skip/blocked paths (debug builds)
- ✅ **Canonical balance apply** - `refreshPointStateAfterPollWin` applies authoritative server balance when local headline diverges

#### Engagement Hub & Carousel (25 May 2026)
- ✅ **Smarter feed polling** - Engagement provider defers refresh while auto-run poll is in result or countdown
- ✅ **Carousel stability** - Diff guards and layout polish for long multi-option poll timer strips
- ✅ **`opt_*` JSON keys** - Backend emits `opt_0`, `opt_1` keys so PHP does not collapse numeric maps into arrays
- ✅ **Client `opt_*` parsing** - `poll_display_helpers` normalizes `opt_N` and legacy index keys interchangeably
- ✅ **Plugin README refresh** - Professional docs for `twork-rewards-system` and `twork-fcm-notify`

### Recent Updates (May 2026)

#### Live Poll Option Totals
- ✅ **`poll_option_totals` API** - WordPress rewards plugin attaches global per-option PNP snapshots during open/countdown voting without leaking winner data
- ✅ **Engagement model** - `EngagementItem.pollOptionTotals` parsed from feed, interact, and delta-update payloads
- ✅ **Provider cache sync** - `_pollOptionTotalsEquals` diff guard prevents redundant carousel rebuilds while totals stay fresh
- ✅ **Timer strip formatter** - `formatPollGlobalOptionTotalsLine()` renders `Option N: amount` with pending fallback
- ✅ **Scrollable timer UI** - Centered horizontal scroll replaces scaled/ellipsis layouts for long multi-option polls
- ✅ **Vote-count resilience** - Sparse or short vote-count arrays pad to option length instead of failing resolution

#### Poll & Balance Polish (May 2026)
- ✅ **Session-scoped auth sync** - Poll-win point reconciliation after countdown (see prior May commits)
- ✅ **Deferred balance refresh** - Balance headline refresh deferred until poll cadence settles
- ✅ **My PNP balance UI** - Restored when server returns an unchanged headline total

### Previous Updates (January 2026)

#### Authentication & Security Enhancements
- ✅ **Token Caching System** - Implemented synchronous token caching for immediate access and improved authentication flow
- ✅ **User Account Switching** - Enhanced user account switching detection with proper cache clearing across all providers
- ✅ **Push Notification Security** - Added background notification user verification to prevent cross-user notifications
- ✅ **Token Synchronization** - Improved token refresh mechanism with ensureTokenSynchronized method

#### Point System Improvements
- ✅ **Transaction Sorting** - Fixed transaction ordering with proper date-based sorting (newest first) for consistent display
- ✅ **User Account Handling** - Enhanced point provider with proper user account switching and cache management
- ✅ **Transaction Status Detection** - Improved detection of pending to approved transaction transitions
- ✅ **Debounced Notifications** - Added debounced UI updates to prevent excessive rebuilds and improve performance
- ✅ **Engagement Point Detection** - Enhanced point earning with automatic engagement point type detection
- ✅ **API Parameter Support** - Added orderby and order parameter support for transaction API endpoints

#### Engagement System Enhancements
- ✅ **Real-Time Feed Updates** - Implemented automatic polling for near real-time engagement feed updates
- ✅ **Feed Management** - Enhanced engagement feed loading with force refresh and debouncing
- ✅ **Quiz Data Parsing** - Improved quiz data parsing with support for multiple status formats
- ✅ **Rotation Duration** - Added rotation duration validation and default handling for engagement carousel
- ✅ **Error Handling** - Enhanced error handling and logging throughout engagement flow

#### UI/UX Improvements
- ✅ **Screen Enhancements** - Improved authentication screens with better error handling and validation
- ✅ **Main Page Integration** - Enhanced main page with better engagement hub integration and deep linking
- ✅ **Point History Page** - Improved transaction display with better filtering and sorting
- ✅ **Theme Updates** - Enhanced app theming for consistent UI across the application
- ✅ **Loading States** - Added better loading states and error handling across all screens

#### Service & Infrastructure Improvements
- ✅ **Push Notification Service** - Enhanced notification routing and deep linking with better error recovery
- ✅ **WordPress Plugins** - Improved API endpoints with better error handling and validation
- ✅ **Build Configuration** - Updated dependencies and added development scripts for Android development
- ✅ **Performance Optimization** - Optimized connectivity service usage with cached instances

#### Previous Updates
- ✅ **App Update Service** - Dynamic app update notifications and version management
- ✅ **Point Notification System** - Enhanced point notifications with modal popups
- ✅ **Exchange Settings Provider** - Improved reward exchange settings management

---

---

## 👥 Project Information

### Author
**Maw Kunn Myat** - Original developer and architect of the Mingalarbuy platform

### Maintained By
**T-Work System** - Professional software development and maintenance

### Contact Information
- **Email**: support@tworksystem.com
- **Website**: [www.tworksystem.com](https://www.tworksystem.com)
- **Store**: [mingalarbuy.com](https://mingalarbuy.com)
- **GitHub**: [@mawkunnmyat](https://github.com/mawkunnmyat)

### Project Repository
- **Primary**: [github.com/mawkunnmyat/mingalarbuy](https://github.com/mawkunnmyat/mingalarbuy)
- **Organization mirror**: [github.com/tworksystem/mingalarbuy](https://github.com/tworksystem/mingalarbuy)
- **Issues**: [GitHub Issues](https://github.com/mawkunnmyat/mingalarbuy/issues)
- **Documentation**: See `docs/` folder for detailed guides

---

<div align="center">

**Made with ❤️ by the T-Work Team**

**Author**: Maw Kunn Myat | **Maintained by**: T-Work System | **Repo**: [mawkunnmyat/mingalarbuy](https://github.com/mawkunnmyat/mingalarbuy)

[⬆ Back to Top](#mingalarbuy---planetmm-e-commerce-platform)

</div>
