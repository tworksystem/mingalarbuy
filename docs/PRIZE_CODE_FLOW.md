# Prize Code System Flow

## Overview
The prize code system is **completely separate** from the point system. Prize codes **ONLY** affect wallet balance, never points.

## Clean Flow

```
1. User enters code
   ↓
2. Code is validated (real-time)
   ↓
3. User clicks "Claim Prize"
   ↓
4. Code is claimed via API
   ↓
5. prizeValue is added to wallet balance ONLY
   ↓
6. Wallet balance updates in:
   Profile Page → Wallet → Payment → Current account balance
```

## Key Points

### ✅ What Prize Codes Do:
- **ONLY** update wallet balance
- Add `prizeValue` to "Current account balance" in Profile → Wallet → Payment
- Never touch the point system

### ❌ What Prize Codes DON'T Do:
- Do NOT affect point balance
- Do NOT interact with PointProvider
- Do NOT use PointService
- Do NOT modify "My Points" section

## Implementation Details

### Service Layer (`PrizeCodeService`)
- `validatePrizeCode()` - Validates code, returns `prizeValue`
- `claimPrizeCode()` - Claims code, returns claim result
- **Note:** `prizePoints` field exists for API backward compatibility but is always `0`

### Provider Layer (`WalletProvider`)
- `addToBalance()` - Adds `prizeValue` to wallet balance
- Updates wallet balance state
- Triggers UI updates via `notifyListeners()`

### UI Layer (`PrizeCodeDialog`)
- Shows code input field
- Real-time validation
- Claims code on button click
- Updates wallet balance via `WalletProvider.addToBalance()`

### Display Layer (`WalletPage`)
- Shows "Current account balance" in Profile → Wallet → Payment
- Uses `Consumer<WalletProvider>` to react to balance changes
- Updates immediately when balance changes

## Code Structure

```
lib/
├── services/
│   └── prize_code_service.dart      # Prize code API calls (NO point system)
├── providers/
│   └── wallet_provider.dart         # Wallet balance management (NO point system)
└── widgets/
    └── prize_code_dialog.dart       # Prize code UI (NO point system)
```

## Testing

### Test Codes (Debug Mode Only):
- `TEST100` → Adds $10.00 to wallet
- `TEST500` → Adds $50.00 to wallet
- `TEST1000` → Adds $100.00 to wallet
- `WELCOME` → Adds $5.00 to wallet
- `PRIZE2024` → Adds $25.00 to wallet

### Verification:
1. Enter test code (e.g., `TEST100`)
2. Claim prize
3. Check Profile → Wallet → Payment → Current account balance
4. Balance should increase by prize value
5. **Point balance should NOT change**

## API Compatibility

The `prizePoints` field is kept in API responses for backward compatibility but:
- Always set to `0`
- Never used in the application
- Clearly documented as "not used"
- Kept only for API compatibility

## Best Practices

1. **Separation of Concerns**: Prize codes and points are completely separate systems
2. **Clear Documentation**: All methods clearly state they only affect wallet balance
3. **No Point System Dependencies**: Prize code system has zero dependencies on point system
4. **Professional Code Style**: Clean, well-documented, maintainable code

