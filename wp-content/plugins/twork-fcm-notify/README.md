# T-Work FCM Notify

A professional WordPress plugin that integrates Firebase Cloud Messaging (FCM) with WooCommerce to send push notifications when order statuses change. Built with security and best practices in mind.

## 🚀 Features

- **RESTful API Integration**: Register and manage FCM device tokens via REST endpoints
- **Automatic Notifications**: Sends push notifications automatically when WooCommerce order statuses change
- **Multi-Platform Support**: Handles both Android and iOS devices
- **Token Management**: Efficiently manages multiple tokens per user with automatic deduplication
- **Firebase v1 API**: Uses the latest FCM HTTP v1 API for reliable message delivery
- **Security First**: Implements proper sanitization, validation, and secure authentication
- **Debug Endpoints**: Built-in debugging endpoints for development and troubleshooting

## 📋 Requirements

- WordPress 5.0 or higher
- WooCommerce 3.0 or higher
- PHP 7.4 or higher (with OpenSSL extension)
- Firebase Project with FCM enabled
- Service Account JSON key from Firebase Console

## 📦 Installation

### 1. Clone or Download

```bash
cd wp-content/plugins
git clone https://github.com/tworksystem/twork-fcm-notify.git
```

### 2. Configure Firebase

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (or create a new one)
3. Navigate to **Project Settings** → **Service accounts**
4. Click **Generate new private key**
5. Download the JSON file and save it as `serviceAccountKey.json` in the plugin directory
6. **IMPORTANT**: Copy `serviceAccountKey.json.example` to `serviceAccountKey.json` and fill in your actual credentials:
   ```bash
   cp serviceAccountKey.json.example serviceAccountKey.json
   # Then edit serviceAccountKey.json with your actual Firebase credentials
   ```

### 3. Configure Plugin

Edit `twork-fcm-notify.php` and update the Firebase project ID:

```php
define('TWORK_FCM_PROJECT_ID', 'your-firebase-project-id');
```

### 4. Activate Plugin

1. Go to WordPress Admin → Plugins
2. Find **T-Work FCM Notify** and click **Activate**

## 🔧 Configuration

### Environment Variables

The plugin uses the following constants (defined in the main plugin file):

- `TWORK_FCM_PROJECT_ID`: Your Firebase project ID
- `TWORK_FCM_SERVICE_ACCOUNT_JSON`: Path to your service account JSON file (default: `__DIR__ . '/serviceAccountKey.json'`)

## 📡 API Endpoints

### Register/Update FCM Token

Register or update a device's FCM token for a user.

**Endpoint:** `POST /wp-json/twork/v1/register-token`

**Request Body:**
```json
{
  "userId": "123",
  "fcmToken": "your-fcm-token-here",
  "platform": "android" // optional: "android" or "ios", defaults to "android"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "tokenCount": 2
}
```

**Error Response (400):**
```json
{
  "success": false,
  "error": "userId and fcmToken required"
}
```

### Debug: View User Tokens

View all FCM tokens registered for a specific user (tokens are masked for security).

**Endpoint:** `GET /wp-json/twork/v1/debug/tokens/{user_id}`

**Success Response (200):**
```json
{
  "userId": 123,
  "tokens": [
    {
      "token": "dP0X4xGxR5y3z8vW2mN6kL9hJ...",
      "platform": "android",
      "updated_at": 1704067200
    }
  ]
}
```

## 🔔 Notification Behavior

The plugin automatically sends push notifications when a WooCommerce order status changes to:

- `pending` - "Order #123 is being processed"
- `processing` - "Order #123 is being prepared"
- `on-hold` - "Order #123 is on hold"
- `completed` - "Order #123 has been completed"
- `cancelled` - "Order #123 has been cancelled"
- `refunded` - "Order #123 has been refunded"
- `failed` - "Order #123 payment failed"
- `shipped` - "Order #123 has been shipped"

### Notification Payload

Each notification includes the following data:

```json
{
  "orderId": "123",
  "status": "completed",
  "total": "99.99",
  "currency": "USD",
  "type": "order_status_update",
  "userId": "456",
  "user_id": "456"
}
```

## 🛡️ Security Considerations

### Critical Security Notes

- ✅ All input parameters are sanitized using WordPress functions
- ✅ Service account credentials are stored locally (never exposed via API)
- ✅ Token deduplication prevents duplicate registrations
- ✅ Error logging is implemented for debugging without exposing sensitive data
- ⚠️ **CRITICAL**: Never commit `serviceAccountKey.json` to version control (it's in `.gitignore`)
- ⚠️ **If credentials were ever committed**: Regenerate your Firebase service account key immediately
- ✅ Use environment variables or secure credential storage in production
- ✅ Restrict file permissions: `chmod 600 serviceAccountKey.json`
- ✅ Keep service account keys on a need-to-know basis

### File Permissions

After creating `serviceAccountKey.json`, set restrictive permissions:

```bash
chmod 600 serviceAccountKey.json
chown www-data:www-data serviceAccountKey.json  # Adjust user/group for your server
```

### Credential Rotation

If your service account key was ever exposed:
1. Go to Firebase Console → Project Settings → Service Accounts
2. Delete the old service account key
3. Generate a new private key
4. Update `serviceAccountKey.json` with the new credentials
5. Test the plugin to ensure notifications work

## 📝 Code Architecture

### Main Functions

- `twork_register_fcm_token()`: Handles FCM token registration/updates
- `twork_send_fcm()`: Sends push notifications via FCM v1 API
- `twork_get_access_token_from_sa()`: Authenticates with Firebase using service account
- `twork_status_message()`: Maps WooCommerce order status to user-friendly messages

### Hooks Used

- `rest_api_init`: Registers REST API endpoints
- `woocommerce_order_status_changed`: Triggers notifications on order status change

## 🐛 Debugging

### Enable WordPress Debug Logging

Add to `wp-config.php`:

```php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
```

Check logs at: `wp-content/debug.log`

### Common Issues

1. **No notifications received**
   - Verify `serviceAccountKey.json` exists and is valid
   - Check Firebase project ID matches
   - Ensure user has registered FCM tokens
   - Review WordPress debug logs

2. **401 Unauthorized errors**
   - Verify service account JSON is valid
   - Check Firebase project permissions
   - Ensure OpenSSL extension is enabled

3. **Tokens not saving**
   - Verify user ID is correct
   - Check database user meta table
   - Use debug endpoint to verify token registration

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: 16012026 - Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Commit Message Format

Please follow the commit message format:

```
feat: 16012026 - Description of the change
```

Prefix types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

## 📄 License

This plugin is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 T-Work System

## 👥 Authors

- **T-Work System** - Initial development

## 🔗 Related Links

- [Firebase Cloud Messaging Documentation](https://firebase.google.com/docs/cloud-messaging)
- [WooCommerce REST API Documentation](https://woocommerce.github.io/woocommerce-rest-api-docs/)
- [WordPress Plugin Development Handbook](https://developer.wordpress.org/plugins/)

## 📞 Support

For issues, questions, or contributions, please open an issue on the [GitHub repository](https://github.com/tworksystem/twork-fcm-notify).

---

**Version:** 1.0.0  
**Last Updated:** January 16, 2026
