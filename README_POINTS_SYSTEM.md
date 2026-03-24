# T-Work Points System - WordPress Integration Guide

## Overview
This document explains how to integrate the T-Work Points System with WordPress WooCommerce for real-time point synchronization.

## WordPress Plugin Installation

### Step 1: Install the Plugin
1. Upload the `twork-points-system` folder to `/wp-content/plugins/` directory
2. Activate the plugin through the 'Plugins' menu in WordPress
3. The plugin will automatically create the necessary database tables

### Step 2: Plugin Features
- **Automatic Point Earning**: Points are automatically awarded when orders are completed
- **Point Redemption**: Users can redeem points for discounts
- **Transaction History**: Complete history of all point transactions
- **REST API Endpoints**: Full API for mobile app integration

## REST API Endpoints

### 1. Get Point Balance
```
GET /wp-json/twork/v1/points/balance/{user_id}
```

**Response:**
```json
{
  "user_id": "123",
  "current_balance": 500,
  "lifetime_earned": 1000,
  "lifetime_redeemed": 300,
  "lifetime_expired": 200,
  "last_updated": "2024-01-15 10:30:00"
}
```

### 2. Get Point Transactions
```
GET /wp-json/twork/v1/points/transactions/{user_id}?page=1&per_page=20
```

**Response:**
```json
{
  "transactions": [
    {
      "id": "1",
      "user_id": "123",
      "type": "earn",
      "points": 100,
      "description": "Points earned from order #456",
      "order_id": "456",
      "created_at": "2024-01-15 10:30:00",
      "expires_at": "2025-01-15 10:30:00",
      "is_expired": false
    }
  ],
  "total": 50,
  "page": 1,
  "per_page": 20,
  "total_pages": 3
}
```

### 3. Earn Points
```
POST /wp-json/twork/v1/points/earn
```

**Body:**
```json
{
  "user_id": "123",
  "points": 100,
  "type": "earn",
  "description": "Points earned from order #456",
  "order_id": "456",
  "expires_at": "2025-01-15T10:30:00Z"
}
```

**Response:**
```json
{
  "success": true,
  "transaction_id": 789,
  "new_balance": 600
}
```

### 4. Redeem Points
```
POST /wp-json/twork/v1/points/redeem
```

**Body:**
```json
{
  "user_id": "123",
  "points": 50,
  "description": "Points redeemed for discount",
  "order_id": "457"
}
```

**Response:**
```json
{
  "success": true,
  "transaction_id": 790,
  "new_balance": 550
}
```

### 5. Sync Points (Bulk Sync)
```
POST /wp-json/twork/v1/points/sync
```

**Body:**
```json
{
  "user_id": "123",
  "transactions": [
    {
      "type": "earn",
      "points": 100,
      "description": "Points earned from order #456",
      "order_id": "456",
      "expires_at": "2025-01-15T10:30:00Z"
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "synced": 1,
  "total": 1,
  "errors": [],
  "new_balance": 600
}
```

## Authentication
All endpoints use WooCommerce API authentication:
- **Header**: `Authorization: Basic {base64_encoded_consumer_key:consumer_secret}`

## Point Configuration

### Default Settings
- **Points Rate**: 1 point per $1 spent (configurable in WordPress options)
- **Redemption Rate**: 100 points = $1 discount (configurable)
- **Signup Bonus**: 100 points (configurable)
- **Point Expiration**: 1 year from earning date

### Configuration Options
You can modify these in WordPress:
- `twork_points_rate` - Points per dollar
- `twork_points_redemption_rate` - Points needed for $1 discount
- `twork_points_signup_bonus` - Signup bonus points

## Automatic Point Earning

### Order Completion
Points are automatically awarded when:
- Order status changes to "completed" or "processing"
- Points are calculated as: `Order Total × Points Rate`
- Points expire 1 year from earning date
- Each order can only award points once

### Example
- Order Total: $100.00
- Points Rate: 1.0
- Points Earned: 100 points
- Expires: 1 year from order completion

## Database Structure

### Table: `wp_twork_point_transactions`
- `id` - Transaction ID
- `user_id` - WordPress User ID
- `type` - Transaction type (earn, redeem, expire, adjust)
- `points` - Points amount
- `description` - Transaction description
- `order_id` - Related order ID
- `created_at` - Transaction date
- `expires_at` - Expiration date (nullable)
- `is_expired` - Expiration status

## Mobile App Integration

### Flutter App Features
1. **Automatic Balance Loading**: Points load automatically on app start and login - no navigation required
2. **Real-time Sync**: Points sync automatically when app goes online
3. **Offline Support**: Points are cached locally for offline viewing
4. **Transaction History**: Full history with pagination
5. **Balance Display**: Current balance shown in profile and throughout the app
6. **Reactive State Management**: Points update automatically when authentication state changes

### Auto-Loading Architecture

The Flutter app implements a sophisticated auto-loading system that ensures points are always available when needed:

#### Components

**1. PointAuthListener Widget**
- Wraps the entire app and listens to authentication state changes
- Automatically triggers point loading when user logs in
- Clears points when user logs out
- Located in `lib/widgets/point_auth_listener.dart`

**2. PointProvider Enhancements**
- `handleAuthStateChange()` method responds to auth state changes
- Smart loading prevents duplicate API calls
- Tracks current user ID to avoid unnecessary reloads
- Enhanced caching with `_cacheBalance()` method

**3. Profile Page Fallback**
- Loads balance when profile page opens as a safety net
- Ensures points display even if auto-load didn't trigger
- Force refresh option for latest balance

#### Loading Flow

```
App Start → PointAuthListener → Check Auth State
    ↓
User Authenticated? → Yes → PointProvider.handleAuthStateChange()
    ↓
Load Balance from API → Cache Locally → Update UI
    ↓
Points Displayed Immediately
```

#### Benefits

✅ **Zero User Action Required**: Points appear automatically  
✅ **Instant Display**: Cached balance shown immediately  
✅ **Always Up-to-Date**: Fresh data fetched in background  
✅ **Offline Resilient**: Works without network connection  
✅ **Efficient**: Prevents unnecessary API calls  
✅ **Professional UX**: Seamless user experience  

### Sync Flow
1. App creates transaction locally (offline)
2. When online, app syncs all local transactions to WordPress
3. WordPress validates and stores transactions
4. App fetches updated balance from WordPress
5. Local cache is updated
6. UI automatically reflects changes via Provider pattern

## Testing

### Test Point Earning
1. Create a test order in WooCommerce
2. Complete the order
3. Check user's point balance via API
4. Verify transaction appears in history

### Test Point Redemption
1. Ensure user has sufficient points
2. Call redeem endpoint with points amount
3. Verify balance decreases correctly
4. Check transaction appears in history

## Troubleshooting

### Points Not Displaying on App Start

**Symptoms**: Points show "0 points" or don't appear until navigating to points page.

**Solutions**:
1. **Check Authentication State**
   - Verify user is properly authenticated
   - Check `AuthProvider.isAuthenticated` is `true`
   - Ensure user ID is available

2. **Verify PointAuthListener**
   - Confirm `PointAuthListener` wraps `MaterialApp` in `main.dart`
   - Check console logs for "User authenticated, loading point balance"
   - Verify no errors in `PointAuthListener`

3. **Check PointProvider State**
   - Verify `PointProvider` is registered in `MultiProvider`
   - Check `pointProvider.balance` is not null after loading
   - Review logs for API call success/failure

4. **Network Issues**
   - Check internet connectivity
   - Verify backend URL is correct in `app_config.dart`
   - Check API endpoint is accessible
   - Review cached balance as fallback

5. **Force Refresh**
   - Navigate to profile page (triggers fallback loading)
   - Pull to refresh if available
   - Restart app to trigger auto-load

**Debug Steps**:
```dart
// Check auth state
final authProvider = Provider.of<AuthProvider>(context, listen: false);
print('Authenticated: ${authProvider.isAuthenticated}');
print('User ID: ${authProvider.user?.id}');

// Check point state
final pointProvider = Provider.of<PointProvider>(context, listen: false);
print('Balance: ${pointProvider.balance?.currentBalance}');
print('Loading: ${pointProvider.isLoading}');
print('Error: ${pointProvider.errorMessage}');
```

### Points Not Awarded
- Check if order status is "completed" or "processing"
- Verify `_points_awarded` meta is not already set
- Check WordPress error logs

### API Authentication Failed
- Verify WooCommerce API credentials
- Check consumer key and secret are correct
- Ensure Basic Auth header is properly encoded

### Balance Not Updating
- Clear WordPress cache
- Check database for transactions
- Verify user meta `points_balance` is updated
- Check if `PointProvider` is properly notifying listeners
- Verify `PointAuthListener` is detecting auth state changes

## Support
For issues or questions, contact: support@tworksystem.com

