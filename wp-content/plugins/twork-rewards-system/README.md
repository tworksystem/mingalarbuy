# T-Work Rewards System

A comprehensive WordPress plugin for managing a rewards and points system integrated with WooCommerce. This plugin enables e-commerce sites to implement a full-featured loyalty program with points, tiers, transactions, and user management.

## 📋 Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [API Documentation](#api-documentation)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)
- [Author](#author)

## ✨ Features

### Core Functionality
- **Points Management**: Automatic points creation when orders are placed
- **Transaction System**: Complete transaction history with pending, completed, and cancelled states
- **Tier System**: Multi-level membership tiers with bonus point multipliers
- **User Profile Integration**: Seamless integration with WordPress user profiles
- **Admin Dashboard**: Comprehensive admin interface for managing rewards, points, and users

### Advanced Features
- **Lucky Box System**: Configurable lucky box feature with banner support
- **REST API**: Full REST API for mobile app integration
- **Usage Tracking**: Track app usage with device information and version tracking
- **Export Functionality**: Export user data and transaction history
- **Activity Scoring**: User activity scoring system with configurable weights
- **Real-time Updates**: Optional real-time updates for user pages
- **Caching System**: Performance optimization with configurable caching
- **Bulk Actions**: Efficient bulk operations for user management

### Admin Features
- **Points Management**: Set, adjust, and manage user points
- **Tier Configuration**: Create and manage membership tiers
- **Transaction Overview**: View and manage all reward transactions
- **User Management**: Comprehensive user page with filtering, sorting, and search
- **Settings Panel**: Extensive configuration options
- **App Update Management**: Manage app version updates and notifications

## 🔧 Requirements

- **WordPress**: 5.0 or higher
- **PHP**: 7.4 or higher
- **WooCommerce**: 5.0 or higher
- **MySQL/MariaDB**: 5.6 or higher

## 📦 Installation

### Manual Installation

1. Download the plugin files
2. Upload the `twork-rewards-system` folder to `/wp-content/plugins/` directory
3. Activate the plugin through the 'Plugins' menu in WordPress
4. Navigate to **T-Work Rewards** in the admin menu to configure settings

### Via Git

```bash
cd wp-content/plugins
git clone https://github.com/tworksystem/twork-points-system.git twork-rewards-system
```

## ⚙️ Configuration

### Initial Setup

1. **Activate the Plugin**: The plugin will automatically create necessary database tables upon activation
2. **Configure Points**: Set default points values in the admin settings
3. **Set Up Tiers**: Create membership tiers with appropriate point thresholds and multipliers
4. **Configure Lucky Box**: Enable and configure the lucky box feature if needed

### Settings Overview

- **General Settings**: Configure default points, transaction settings, and system behavior
- **Tier Management**: Create and manage membership tiers
- **User Page Settings**: Customize user management page display and functionality
- **App Update Settings**: Manage mobile app version updates
- **Lucky Box Settings**: Configure lucky box feature and banner

## 📖 Usage

### For Administrators

#### Managing User Points

1. Navigate to **Users** → **All Users**
2. Click on a user to edit their profile
3. Scroll to the **T-Work Rewards** section
4. Adjust points as needed
5. Click **Update User** to save changes

#### Creating Transactions

Transactions are automatically created when:
- A new WooCommerce order is placed
- Points are manually adjusted by admin
- Points are redeemed or used

#### Managing Tiers

1. Go to **T-Work Rewards** → **Point Tiers**
2. Click **Add New Tier** or edit existing tiers
3. Configure tier settings:
   - Name and slug
   - Level and point thresholds
   - Bonus multiplier
   - Color and icon
   - Description and benefits
4. Save the tier

### For Developers

#### REST API Endpoints

The plugin provides comprehensive REST API endpoints for mobile app integration:

- `GET /wp-json/twork/v1/points/{user_id}` - Get user points
- `GET /wp-json/twork/v1/wallet/{user_id}` - Get user wallet balance
- `GET /wp-json/twork/v1/tier/{user_id}` - Get user tier information
- `POST /wp-json/twork/v1/usage/start` - Track app usage
- `GET /wp-json/twork/v1/transactions/{user_id}` - Get user transactions
- `GET /wp-json/twork/v1/app-update` - Get app update information

#### Hooks and Filters

The plugin provides various WordPress hooks for customization:

```php
// Action: After points are updated
do_action('twork_rewards_points_updated', $user_id, $points, $transaction_id);

// Filter: Modify points calculation
apply_filters('twork_rewards_calculate_points', $points, $order_id);
```

## 🔌 API Documentation

### Authentication

All API endpoints require authentication. Use WordPress REST API authentication methods:
- Cookie authentication (for logged-in users)
- Application passwords
- OAuth 2.0 (if configured)

### Response Format

All API responses follow this format:

```json
{
  "success": true,
  "data": {
    // Response data
  }
}
```

### Error Responses

```json
{
  "success": false,
  "error": {
    "code": "error_code",
    "message": "Error message"
  }
}
```

## 🛠️ Development

### Project Structure

```
twork-rewards-system/
├── twork-rewards-system.php  # Main plugin file
├── README.md                 # This file
├── LICENSE                   # License file
└── .gitignore               # Git ignore file
```

### Database Schema

The plugin creates the following database tables:

- `wp_twork_rewards_transactions` - Transaction history
- `wp_twork_rewards_point_tiers` - Membership tiers
- `wp_twork_rewards_usage` - App usage tracking
- `wp_twork_rewards_codes` - Reward codes

### Code Standards

- Follow WordPress Coding Standards
- Use proper escaping and sanitization
- Implement proper nonce verification
- Follow PSR-12 for PHP code style

### Testing

Before deploying:

1. Test on a staging environment
2. Verify database migrations
3. Test all API endpoints
4. Verify WooCommerce integration
5. Test user role permissions

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: 16012026 - Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Commit Message Format

Follow the conventional commit format:

```
feat: 16012026 - Add new feature
fix: 16012026 - Fix bug description
docs: 16012026 - Update documentation
refactor: 16012026 - Refactor code
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👤 Author

**Maw Kunn Myat**

- **Primary Email**: mapoeeiphyu2017.miitinternship@gmail.com
- **Support Email**: support@tworksystem.com
- **GitHub**: [@mawkunnmyat](https://github.com/mawkunnmyat)
- **Organization**: T-WORK SYSTEM Co.,Ltd.

## 🙏 Acknowledgments

- WordPress Community
- WooCommerce Team
- All contributors and users of this plugin

## 📞 Support

For support and inquiries:
- **GitHub Issues**: [Open an issue](https://github.com/tworksystem/twork-points-system/issues)
- **Email**: support@tworksystem.com
- **Developer Contact**: mapoeeiphyu2017.miitinternship@gmail.com

## 🔗 Links

- **Repository**: [https://github.com/tworksystem/twork-points-system](https://github.com/tworksystem/twork-points-system)
- **Issues**: [https://github.com/tworksystem/twork-points-system/issues](https://github.com/tworksystem/twork-points-system/issues)
- **Releases**: [https://github.com/tworksystem/twork-points-system/releases](https://github.com/tworksystem/twork-points-system/releases)

---

**Version**: 1.0.0  
**Last Updated**: January 16, 2026  
**Maintained by**: Maw Kunn Myat  
**Organization**: T-WORK SYSTEM Co.,Ltd.
