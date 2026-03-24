# Prize Code Test Codes

## Development/Testing Codes

These codes work **only in Debug Mode** for testing purposes. They will automatically work when the backend API is not available or when testing offline.

### Available Test Codes

| Code | Prize Value | Description |
|------|-------------|-------------|
| `TEST100` | $10.00 | Test Prize - $10 |
| `TEST500` | $50.00 | Test Prize - $50 |
| `TEST1000` | $100.00 | Test Prize - $100 |
| `WELCOME` | $5.00 | Welcome Bonus |
| `PRIZE2024` | $25.00 | 2024 Special Prize |

### How to Use

1. Open the app in **Debug Mode** (development build)
2. Click "Get Code" button
3. Enter any of the test codes above
4. The code will be validated automatically
5. Click "Claim Prize" to add the amount to your wallet

### Features

- ✅ Works offline (no backend API required)
- ✅ Real-time validation
- ✅ Automatically adds to wallet balance
- ✅ Shows in Wallet page immediately
- ✅ Only available in Debug Mode (not in production)

### Notes

- Test codes are case-insensitive (e.g., `test100` = `TEST100`)
- Each code can be used multiple times in test mode
- The wallet balance will update immediately after claiming
- In production builds, these codes will not work - only real API codes will work

### Testing Flow

1. **Enter Code**: Type `TEST100` in the prize code field
2. **Validation**: You'll see a green checkmark and "$10.00 will be added to your wallet"
3. **Claim**: Click "Claim Prize" button
4. **Success**: You'll see a success message
5. **Check Wallet**: Go to Profile → Wallet to see the updated balance

### Production Codes

When the backend API is implemented, real prize codes will be managed through the WordPress admin panel. Test codes will automatically be disabled in production builds.

