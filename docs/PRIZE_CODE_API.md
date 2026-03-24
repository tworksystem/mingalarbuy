# Prize Code API Documentation

## Overview
This document describes the REST API endpoints required for the prize code feature in the T-Work Commerce app.

## Endpoints

### 1. Validate Prize Code
**Endpoint:** `GET /wp-json/twork/v1/prize/validate`

**Query Parameters:**
- `code` (required): The prize code to validate
- `consumer_key`: WooCommerce consumer key
- `consumer_secret`: WooCommerce consumer secret

**Response (Valid Code):**
```json
{
  "valid": true,
  "code": "PRIZE123",
  "prize_value": 10.00,
  "prize_points": 0,
  "description": "Special promotion prize",
  "message": "Code is valid"
}
```

**Note:** `prize_value` is the amount that will be added to the wallet balance. `prize_points` is kept for backward compatibility but should be 0 for wallet-based prizes.

**Response (Invalid Code):**
```json
{
  "valid": false,
  "code": "INVALID",
  "message": "Invalid or expired code"
}
```

**Error Codes:**
- `invalid_code`: Code does not exist
- `code_expired`: Code has expired
- `code_already_used`: Code has already been claimed
- `code_inactive`: Code is not active

---

### 2. Claim Prize Code
**Endpoint:** `POST /wp-json/twork/v1/prize/claim`

**Query Parameters:**
- `consumer_key`: WooCommerce consumer key
- `consumer_secret`: WooCommerce consumer secret

**Request Body:**
```json
{
  "user_id": "123",
  "code": "PRIZE123"
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Prize claimed successfully!",
  "prize_value": 10.00,
  "prize_points": 0,
  "new_wallet_balance": 64.24,
  "transaction_id": "789"
}
```

**Note:** `new_wallet_balance` is the updated wallet balance after adding the prize value. This is the balance shown in the Wallet page.

**Response (Failure):**
```json
{
  "success": false,
  "message": "Code has already been used"
}
```

**Error Codes:**
- `invalid_code`: Code does not exist
- `code_expired`: Code has expired
- `code_already_used`: Code has already been claimed
- `code_inactive`: Code is not active
- `user_not_found`: User ID is invalid
- `insufficient_permissions`: User does not have permission

---

## WordPress Plugin Implementation

### Database Table Structure

#### Prize Codes Table

Create a table for prize codes:

```sql
CREATE TABLE wp_twork_prize_codes (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    code VARCHAR(50) NOT NULL UNIQUE,
    prize_value DECIMAL(10,2) DEFAULT 0.00,
    prize_points INT(11) DEFAULT 0,
    description TEXT,
    max_uses INT(11) DEFAULT 1,
    current_uses INT(11) DEFAULT 0,
    expires_at DATETIME NULL,
    is_active TINYINT(1) DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_code (code),
    INDEX idx_active (is_active),
    INDEX idx_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### PHP Implementation Example

Add to `twork-points-system.php`:

```php
/**
 * Register prize code REST API routes
 */
public function register_rest_routes() {
    // ... existing routes ...
    
    // Validate prize code
    register_rest_route('twork/v1', '/prize/validate', array(
        'methods' => 'GET',
        'callback' => array($this, 'validate_prize_code'),
        'permission_callback' => array($this, 'check_woocommerce_auth'),
    ));
    
    // Claim prize code
    register_rest_route('twork/v1', '/prize/claim', array(
        'methods' => 'POST',
        'callback' => array($this, 'claim_prize_code'),
        'permission_callback' => array($this, 'check_woocommerce_auth'),
    ));
}

/**
 * Validate prize code
 */
public function validate_prize_code($request) {
    $code = sanitize_text_field($request->get_param('code'));
    
    if (empty($code)) {
        return new WP_Error('invalid_code', 'Code is required', array('status' => 400));
    }
    
    global $wpdb;
    $table_name = $wpdb->prefix . 'twork_prize_codes';
    
    $prize = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM $table_name WHERE code = %s",
        $code
    ));
    
    if (!$prize) {
        return rest_ensure_response(array(
            'valid' => false,
            'code' => $code,
            'message' => 'Invalid code'
        ));
    }
    
    // Check if code is active
    if (!$prize->is_active) {
        return rest_ensure_response(array(
            'valid' => false,
            'code' => $code,
            'message' => 'Code is not active'
        ));
    }
    
    // Check if code has expired
    if ($prize->expires_at && strtotime($prize->expires_at) < time()) {
        return rest_ensure_response(array(
            'valid' => false,
            'code' => $code,
            'message' => 'Code has expired'
        ));
    }
    
    // Check if code has reached max uses
    if ($prize->current_uses >= $prize->max_uses) {
        return rest_ensure_response(array(
            'valid' => false,
            'code' => $code,
            'message' => 'Code has already been used'
        ));
    }
    
    return rest_ensure_response(array(
        'valid' => true,
        'code' => $code,
        'prize_value' => floatval($prize->prize_value),
        'prize_points' => intval($prize->prize_points),
        'description' => $prize->description,
        'message' => 'Code is valid'
    ));
}

/**
 * Claim prize code
 */
public function claim_prize_code($request) {
    $params = $request->get_json_params();
    $user_id = intval($params['user_id'] ?? 0);
    $code = sanitize_text_field($params['code'] ?? '');
    
    if (!$user_id || empty($code)) {
        return new WP_Error('invalid_params', 'User ID and code are required', array('status' => 400));
    }
    
    global $wpdb;
    $table_name = $wpdb->prefix . 'twork_prize_codes';
    
    // Validate code first
    $prize = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM $table_name WHERE code = %s FOR UPDATE",
        $code
    ));
    
    if (!$prize) {
        return rest_ensure_response(array(
            'success' => false,
            'message' => 'Invalid code'
        ));
    }
    
    // Check if code is active
    if (!$prize->is_active) {
        return rest_ensure_response(array(
            'success' => false,
            'message' => 'Code is not active'
        ));
    }
    
    // Check if code has expired
    if ($prize->expires_at && strtotime($prize->expires_at) < time()) {
        return rest_ensure_response(array(
            'success' => false,
            'message' => 'Code has expired'
        ));
    }
    
    // Check if code has reached max uses
    if ($prize->current_uses >= $prize->max_uses) {
        return rest_ensure_response(array(
            'success' => false,
            'message' => 'Code has already been used'
        ));
    }
    
    // Check if user has already claimed this code
    $claims_table = $wpdb->prefix . 'twork_prize_claims';
    $existing_claim = $wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM $claims_table WHERE user_id = %d AND code = %s",
        $user_id,
        $code
    ));
    
    if ($existing_claim > 0) {
        return rest_ensure_response(array(
            'success' => false,
            'message' => 'You have already claimed this code'
        ));
    }
    
    // Start transaction
    $wpdb->query('START TRANSACTION');
    
    try {
        // Update prize code usage
        $wpdb->update(
            $table_name,
            array('current_uses' => $prize->current_uses + 1),
            array('code' => $code),
            array('%d'),
            array('%s')
        );
        
        // Record claim
        $wpdb->insert(
            $claims_table,
            array(
                'user_id' => $user_id,
                'code' => $code,
                'prize_value' => $prize->prize_value,
                'prize_points' => $prize->prize_points,
                'claimed_at' => current_time('mysql')
            ),
            array('%d', '%s', '%f', '%d', '%s')
        );
        
        // Add prize value to wallet balance
        $wallet_table = $wpdb->prefix . 'twork_wallet_balance';
        
        // Get current wallet balance
        $current_wallet = $wpdb->get_var($wpdb->prepare(
            "SELECT balance FROM $wallet_table WHERE user_id = %d",
            $user_id
        ));
        
        if ($current_wallet === null) {
            // Create wallet entry if doesn't exist
            $wpdb->insert(
                $wallet_table,
                array(
                    'user_id' => $user_id,
                    'balance' => $prize->prize_value,
                    'updated_at' => current_time('mysql')
                ),
                array('%d', '%f', '%s')
            );
            $new_wallet_balance = $prize->prize_value;
        } else {
            // Update wallet balance
            $new_wallet_balance = floatval($current_wallet) + floatval($prize->prize_value);
            $wpdb->update(
                $wallet_table,
                array(
                    'balance' => $new_wallet_balance,
                    'updated_at' => current_time('mysql')
                ),
                array('user_id' => $user_id),
                array('%f', '%s'),
                array('%d')
            );
        }
        
        // Record wallet transaction
        $wallet_transactions_table = $wpdb->prefix . 'twork_wallet_transactions';
        $wpdb->insert(
            $wallet_transactions_table,
            array(
                'user_id' => $user_id,
                'type' => 'credit',
                'amount' => $prize->prize_value,
                'description' => $prize->description ?: "Prize code: $code",
                'reference' => $code,
                'created_at' => current_time('mysql')
            ),
            array('%d', '%s', '%f', '%s', '%s', '%s')
        );
        
        $transaction_id = $wpdb->insert_id;
        
        $wpdb->query('COMMIT');
        
        return rest_ensure_response(array(
            'success' => true,
            'message' => 'Prize claimed successfully!',
            'prize_value' => floatval($prize->prize_value),
            'prize_points' => 0,
            'new_wallet_balance' => $new_wallet_balance,
            'transaction_id' => $transaction_id
        ));
        
    } catch (Exception $e) {
        $wpdb->query('ROLLBACK');
        return new WP_Error('claim_failed', 'Failed to claim prize: ' . $e->getMessage(), array('status' => 500));
    }
}
```

#### Prize Claims Table

```sql
CREATE TABLE wp_twork_prize_claims (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT(20) UNSIGNED NOT NULL,
    code VARCHAR(50) NOT NULL,
    prize_value DECIMAL(10,2) DEFAULT 0.00,
    prize_points INT(11) DEFAULT 0,
    claimed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_user_id (user_id),
    INDEX idx_code (code),
    UNIQUE KEY unique_user_code (user_id, code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### Wallet Balance Table

```sql
CREATE TABLE wp_twork_wallet_balance (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT(20) UNSIGNED NOT NULL UNIQUE,
    balance DECIMAL(10,2) DEFAULT 0.00,
    currency VARCHAR(3) DEFAULT 'USD',
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### Wallet Transactions Table

```sql
CREATE TABLE wp_twork_wallet_transactions (
    id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT(20) UNSIGNED NOT NULL,
    type ENUM('credit', 'debit') NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    description TEXT,
    reference VARCHAR(100),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### Wallet Balance API Endpoints

#### Get Wallet Balance
**Endpoint:** `GET /wp-json/twork/v1/wallet/balance/{user_id}`

**Response:**
```json
{
  "user_id": "123",
  "current_balance": 64.24,
  "currency": "USD",
  "last_updated": "2024-01-15 10:30:00"
}
```

#### Add to Wallet Balance
**Endpoint:** `POST /wp-json/twork/v1/wallet/add`

**Request Body:**
```json
{
  "user_id": "123",
  "amount": 10.00,
  "description": "Prize code: PRIZE123"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Balance updated successfully",
  "new_balance": 64.24,
  "currency": "USD",
  "transaction_id": "789"
}
```

## Admin Interface

You may want to create an admin interface to:
- Create new prize codes
- View prize code usage
- Deactivate/activate codes
- Set expiration dates
- Set max uses per code

## Testing

Test the endpoints using curl or Postman:

```bash
# Validate code
curl "https://mingalarbuy.com/wp-json/twork/v1/prize/validate?code=PRIZE123&consumer_key=YOUR_KEY&consumer_secret=YOUR_SECRET"

# Claim code
curl -X POST "https://mingalarbuy.com/wp-json/twork/v1/prize/claim?consumer_key=YOUR_KEY&consumer_secret=YOUR_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "123", "code": "PRIZE123"}'
```

