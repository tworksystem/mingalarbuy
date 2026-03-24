# Poll Winner Notification Recovery System

## 🎯 ပြဿနာ

**အခြေအနေ:**
1. User က poll မှာ vote လုပ်တယ်
2. User က app ကို uninstall လုပ်လိုက်တယ်
3. Poll က ပြီးဆုံးပြီး winner ဆုံးဖြတ်တယ်
4. Backend က database (`wp_twork_point_transactions`) မှာ points ထည့်ပေးတယ် ✅
5. Backend က FCM notification ပို့တယ် → **မရောက်ဘူး** (app uninstalled ဖြစ်လို့) ❌
6. User က app ကို ပြန် install လုပ်ပြီး login ဝင်တယ်
7. Balance က မှန်ကန်စွာ ပြတယ် (points ထည့်ပေးပြီးသား) ✅
8. **ဒါပေမယ့်** "သင် အနိုင်ရပါပြီ!" notification ကို မတွေ့ရဘူး ❌

## ✅ ဖြေရှင်းချက်

**Automatic Recovery System:**
- User က app reinstall လုပ်ပြီး login ဝင်တဲ့အခါ
- System က recent transactions (30 days) ကို automatically check လုပ်တယ်
- "Missed" poll winner notifications တွေကို detect လုပ်တယ်
- In-app notifications အဖြစ် ပြန်လည် ဖန်တီးပေးတယ်
- User က notification center မှာ winner notification ကို မြင်ရမယ် 🎉

## 🔄 လုပ်ဆောင်ပုံ Flow

```
၁။ User login ဝင်တယ်
    ↓
၂။ PointAuthListener က point balance load လုပ်တယ်
    ↓
၃။ MissedNotificationRecoveryService automatic run တယ်
    ↓
၄။ Recent transactions (30 days) ကို စစ်ဆေးတယ်
    ↓
၅။ Poll winner transactions ကို ရှာတယ်
    ↓
၆။ Notification မပို့ရသေးတဲ့ wins တွေကို ရှာတယ်
    ↓
၇။ In-app notifications အသစ် ဖန်တီးပေးတယ်
    ↓
၈။ Notification center မှာ ပေါ်လာတယ် ✅
```

## 📱 User Experience

### Timeline ဥပမာ

**တနင်္လာနေ့:**
- 10:00 AM: "Who will win the championship?" poll မှာ vote လုပ်တယ်
- 10:30 AM: App uninstall လုပ်လိုက်တယ်
- 11:00 AM: Poll ပြီးဆုံးပြီး backend က winner ဆုံးဖြတ်တယ်
- 11:00 AM: 8000 points database မှာ ထည့်ပေးပြီး ✅
- 11:00 AM: FCM notification ပို့တယ် → မရောက်ဘူး ❌

**အင်္ဂါနေ့:**
- 2:00 PM: App reinstall လုပ်ပြီး login ဝင်တယ်
- 2:00 PM: Balance: 8000 points (မှန်ကန်စွာ ပြတယ်) ✅
- 2:00 PM: Recovery system က recent transactions ကို automatic check လုပ်တယ်
- 2:00 PM: မနေ့က poll win transaction ကို တွေ့တယ်
- 2:00 PM: **"Congratulations! You're the Winner! 🏆" notification ဖန်တီးပေးတယ်** ✅
- 2:00 PM: User က notification center မှာ မြင်ရတယ် ✅

**ရလဒ်:** 26 hours ကြာပြီးတောင် user က winner ဖြစ်ကြောင်း သိရတယ်! 🎉

## 🛡️ Duplicate Prevention (တူညီတာ မထပ်ဖြစ်အောင် ကာကွယ်မှု)

### အလွှာ ၃ ခု Protection

**1. Transaction ID Tracking:**
- Notification ပို့ပြီးသား transaction IDs တွေကို မှတ်တမ်းတင်ထားတယ်
- ထပ်မံ recovery လုပ်တဲ့အခါ ကျော်တယ်

**2. InAppNotificationService Deduplication:**
- တူညီတဲ့ `transactionId` က 5 minutes အတွင်း ရှိပြီးသား ဆိုရင် ထပ်မဖန်တီးဘူး

**3. PointNotificationManager Deduplication:**
- Notification keys (type + transaction ID + user ID) ကို သုံးတယ်
- Event တစ်ခုကို notification တစ်ခုသာ ဖန်တီးတယ်

### Edge Cases

**Case 1: FCM စောစောရောက်တယ်**
- FCM က transaction ကို "notified" အဖြစ် mark လုပ်တယ်
- Recovery က ကျော်တယ်
- **ရလဒ်:** Notification တစ်ခုသာ ✅

**Case 2: Recovery က FCM မရောက်ခင် run တယ်**
- Recovery က notification ဖန်တီးပြီး mark လုပ်တယ်
- FCM ရောက်လာတဲ့အခါ duplicate prevention က ရပ်တယ်
- **ရလဒ်:** Notification တစ်ခုသာ ✅

**Case 3: App installed ဖြစ်နေစဉ် popup မြင်တယ်**
- Popup က notification ဖန်တီးတယ် (transaction ID မရှိ)
- FCM ရောက်လာတယ် → transaction ID နဲ့ notification ဖန်တီးတယ်
- Recovery က duplicate prevention ကြောင့် ထပ်မဖန်တီးတော့ဘူး
- **ရလဒ်:** 2 notifications (popup + FCM) ရှိနိုင်တယ်၊ ဒါပေမယ့် 3rd မထပ်ဖြစ်ဘူး ✅

## ⚙️ Configuration

### Automatic Checks
- **Frequency:** 6 hours တစ်ကြိမ် (auto rate-limited)
- **Window:** Recent 30 days transactions
- **When:** App launch, Login, Return from background

### Tracking Storage
- **Type:** SharedPreferences (local device)
- **Auto-cleanup:** App uninstall လုပ်ရင် automatic clear
- **Limit:** Recent 100 transaction IDs သာ သိမ်းတယ်

## 🔍 Poll Winner Detection Rules

Transaction တစ်ခု "poll winner" ဖြစ်ရန် criteria အားလုံး ပြည့်မှီရမယ်:

1. ✅ **Type:** `earn` (winners ကို points ပေးတယ်)
2. ✅ **Status:** `approved` (finalized ဖြစ်ပြီး)
3. ✅ **Order ID:** `"engagement:poll:"` နဲ့ စတယ်
4. ✅ **Description:** `"winner"` သို့မဟုတ် `"Poll winner reward"` ပါတယ်

### Example Detection

**Poll Winner (ဖန်တီးမယ်):**
```json
{
  "id": "12345",
  "type": "earn",
  "status": "approved",
  "points": 8000,
  "order_id": "engagement:poll:789:session:abc:uid",
  "description": "Poll winner reward: Myanmar Premier League (+8000 points)"
}
```

**Poll Entry Cost (ignore လုပ်မယ်):**
```json
{
  "id": "12344",
  "type": "redeem",
  "points": 1000,
  "order_id": "engagement:poll_cost:789:456:xyz",
  "description": "Poll entry fee"
}
```

## 📝 Implementation Files

### ဖန်တီးထားတဲ့ File အသစ်

**1. `lib/services/missed_notification_recovery_service.dart`**
- Core recovery logic
- Transaction detection
- Notification recreation
- Tracking management

### ပြုပြင်ထားတဲ့ Files

**2. `lib/widgets/point_auth_listener.dart`**
- Login အချိန်မှာ recovery service ကို call လုပ်တယ်

**3. `lib/services/push_notification_service.dart`**
- FCM receive လုပ်တဲ့အခါ transaction ID ကို "notified" အဖြစ် mark လုပ်တယ်

**4. `lib/providers/auth_provider.dart`**
- Logout လုပ်တဲ့အခါ tracking data ကို clear လုပ်တယ်

## 🧪 Testing Guide

### Manual Test လုပ်ပုံ

**Test Case 1: App Uninstalled During Poll**
```
1. App login ဝင်တယ်
2. Active poll တစ်ခုမှာ vote လုပ်တယ်
3. App uninstall လုပ်တယ် (သို့မဟုတ် app data clear လုပ်တယ်)
4. Poll ပြီးဆုံးတာ စောင့်တယ် (သို့မဟုတ် backend မှာ manually trigger လုပ်တယ်)
5. Database မှာ points ထည့်ပေးပြီး ဖြစ်ကြောင်း verify လုပ်တယ်
6. App reinstall လုပ်ပြီး login ဝင်တယ်
7. ✅ Notification center မှာ winner notification မြင်ရမယ်
```

**Test Case 2: Multiple Missed Wins**
```
1. Poll 3 ခု မှာ vote လုပ်တယ်
2. App uninstall လုပ်တယ်
3. Poll 3 ခုလုံး ပြီးဆုံးပြီး အားလုံး win တယ်
4. Backend က points 3 ခုလုံး ထည့်ပေးတယ်
5. App reinstall လုပ်ပြီး login ဝင်တယ်
6. ✅ Winner notifications 3 ခု မြင်ရမယ်
```

**Test Case 3: Duplicate Prevention Test**
```
1. Poll vote လုပ်ပြီး win တယ် (FCM normally working)
2. Logout ပြီး login ပြန်ဝင်တယ်
3. ✅ Duplicate notification မပေါ်ရဘူး
```

### Debug Logging

Detailed logs ကြည့်ရန်:

```dart
Logger.setLogLevel(LogLevel.debug);
```

အောက်ပါ log messages တွေ ရှာကြည့်ပါ:
- `Checking for missed poll winner notifications`
- `Found X missed poll winner notification(s)`
- `Recreated notification for missed poll win`
- `Transaction marked as notified`

### Force Check (Testing အတွက်)

Rate limiting ကို bypass လုပ်ပြီး manual check လုပ်ရန်:

```dart
final count = await MissedNotificationRecoveryService.forceCheck(userId);
print('Recovered $count missed notifications');
```

## 🎨 Notification Content

### Title
```
Congratulations! You're the Winner! 🏆
```

### Body Format
```
Poll winner reward: [Poll Title] (+[Points] points)

Example:
"Poll winner reward: Myanmar Premier League Champion 2025 (+8000 points)"
```

### Action
- Notification ကို tap လုပ်ရင် → Point History page သွားတယ်
- အဲ့မှာ full transaction details တွေ့တယ်

## 🔧 Technical Details

### Detection Algorithm

```dart
bool isPollWinnerTransaction(transaction) {
  // 1. Type check
  if (transaction.type != 'earn') return false;
  
  // 2. Status check
  if (transaction.status != 'approved') return false;
  
  // 3. Order ID pattern
  if (!transaction.orderId.startsWith('engagement:poll:')) return false;
  
  // 4. Description keyword
  if (!transaction.description.contains('winner')) return false;
  
  return true; // ✅ This is a poll win!
}
```

### Timing

**When Recovery Runs:**
- App first launch after install
- User login success
- App returns from background (after > 6 hours)

**Rate Limiting:**
- Maximum: Once per 6 hours per user
- Prevents excessive API calls
- Can be forced for testing

### Storage Keys

```
SharedPreferences keys:
- missed_notification_last_check_{userId}    → Last check timestamp
- notified_transaction_ids_{userId}          → List of notified IDs
```

## 🎓 Professional Design Patterns

### 1. Idempotency
- Recovery ကို multiple times run လို့ရတယ်
- Same transaction ကို တစ်ကြိမ်ပဲ notify လုပ်တယ်

### 2. Rate Limiting
- API spam မဖြစ်အောင် ကာကွယ်တယ်
- User experience ကို မထိခိုက်စေဘူး

### 3. Async Execution
- UI ကို block မလုပ်ဘူး
- Background မှာ silent run တယ်

### 4. Defensive Programming
- API failure များ gracefully handle လုပ်တယ်
- Missing data များ handle လုပ်တတ်တယ်

### 5. Automatic Cleanup
- Transaction ID list ကို 100 entries သာ သိမ်းတယ်
- Old IDs များ automatic ဖျက်တယ်
- Memory leak မဖြစ်အောင် ကာကွယ်တယ်

## 🛠️ Backend Integration

### Database Schema

**Table:** `wp_twork_point_transactions`

Poll winner transaction example:
```sql
INSERT INTO wp_twork_point_transactions (
  user_id, 
  type, 
  points, 
  order_id, 
  description, 
  status
) VALUES (
  123,                                          -- winner user_id
  'earn',                                       -- earn points
  8000,                                         -- reward amount
  'engagement:poll:789:session:abc:123',        -- unique order_id
  'Poll winner reward: Poll Title (+8000 points)', -- description
  'approved'                                    -- immediately approved
);
```

### API Endpoint Used

**GET:** `/wp-json/twork/v1/points/transactions/{user_id}`

**Query Parameters:**
- `page=1`
- `per_page=100`
- `orderby=created_at`
- `order=DESC`

**Response:** List of transactions (30 days ကို filter လုပ်တာက frontend မှာ)

## 🚀 Benefits

### For Users
1. ✅ **Never miss winning moments** - App uninstall လုပ်ထားလည်း သိရမယ်
2. ✅ **Seamless experience** - Automatic recovery, no action needed
3. ✅ **Historical wins** - Up to 30 days old wins ကို recover လုပ်ပေးတယ်

### For Developers
1. ✅ **Zero backend changes** - Pure frontend solution
2. ✅ **Reliable** - Works even when FCM fails
3. ✅ **Maintainable** - Clear code, comprehensive logging
4. ✅ **Scalable** - Efficient API usage, proper rate limiting

### For Business
1. ✅ **Better engagement** - Winners always notified
2. ✅ **Trust building** - Points and notifications always synced
3. ✅ **Reduced support** - Fewer "where's my prize?" complaints

## 📊 Monitoring

### Success Metrics

**Recovery Rate:**
```
Number of recovered notifications / Number of missed FCM notifications
Target: > 95%
```

**Response Time:**
```
Time from login to notification appearing
Target: < 3 seconds
```

### Log Messages စစ်ကြည့်ရန်

**Success:**
```
✅ "Checking for missed poll winner notifications"
✅ "Found 2 missed poll winner notification(s)"
✅ "Recreated notification for missed poll win: 12345 (8000 points)"
✅ "Transaction marked as notified: 12345"
```

**Skipped (Rate Limited):**
```
ℹ️ "Skipping missed notification check (last checked 3 hours ago)"
```

**No Missed Wins:**
```
ℹ️ "No missed poll winner notifications found"
```

## 🔮 Future Enhancements

### Planned Features

1. **Backend API Enhancement:**
   - Poll results API က `transaction_id` return လုပ်ပေးမယ်
   - Popup show တဲ့အချိန်မှာ immediate marking လုပ်လို့ရမယ်

2. **Batch Notification Summary:**
   - 5+ missed wins ရှိရင် summary notification ပြမယ်
   - "You won 5 polls while away! Total: 40,000 PNP"

3. **User Preferences:**
   - Recovery window (7/15/30 days) ကို user choose လုပ်လို့ရမယ်
   - Notification preferences (show/hide old wins)

4. **Analytics Dashboard:**
   - Recovery success rate tracking
   - FCM failure patterns identification

## 🆘 Troubleshooting

### Issue: Notifications မ recover ဖြစ်ဘူး

**စစ်ကြည့်ရန်:**
1. PointAuthListener က properly integrated လား?
2. Database မှာ transactions ရှိသလား? (SQL query run ကြည့်)
3. Rate limiting block လုပ်နေလား? (6 hours မကုန်သေးဘူး)
4. Logs မှာ recovery attempt တွေ့လား?

**Debug လုပ်ပုံ:**
```dart
Logger.setLogLevel(LogLevel.debug);
final count = await MissedNotificationRecoveryService.forceCheck(userId);
print('Recovered: $count notifications');
```

### Issue: Duplicate notifications ထပ်ပေါ်တယ်

**စစ်ကြည့်ရန်:**
1. Transaction IDs properly tracked လား?
2. `markTransactionAsNotified` call လုပ်နေလား?
3. InAppNotificationService duplicate prevention work လား?

**Fix လုပ်ပုံ:**
```dart
// Clear tracking and re-sync
await MissedNotificationRecoveryService.clearTrackingForUser(userId);
await MissedNotificationRecoveryService.forceCheck(userId);
```

### Issue: အရမ်းကြာတဲ့ wins တွေ ပြန်ပေါ်တယ်

**အကြောင်းရင်း:** 30-day window က intentional ဖြစ်တယ် (recent wins catch လုပ်ဖို့)

**Solution:**
- 30 days ကို 7 days ဖြစ်အောင် လျှော့ချလို့ရတယ်
- သို့မဟုတ် user preference setting ထည့်လို့ရတယ်

## 📚 Related Files

### Service Layer
- `lib/services/missed_notification_recovery_service.dart` - Core recovery logic
- `lib/services/push_notification_service.dart` - FCM handling + marking
- `lib/services/in_app_notification_service.dart` - Notification creation + deduplication
- `lib/services/point_notification_manager.dart` - Notification orchestration

### Widget Layer
- `lib/widgets/point_auth_listener.dart` - Auto-trigger on login
- `lib/widgets/auto_run_poll_widget.dart` - Auto-run poll winners
- `lib/services/poll_winner_popup_service.dart` - Feed poll winners

### Provider Layer
- `lib/providers/auth_provider.dart` - Logout cleanup
- `lib/providers/point_provider.dart` - Balance management
- `lib/providers/in_app_notification_provider.dart` - Notification state

### Models
- `lib/models/point_transaction.dart` - Transaction data structure
- `lib/models/in_app_notification.dart` - Notification data structure

## ✨ Key Features Summary

| Feature | Description | Status |
|---------|-------------|--------|
| **Auto Recovery** | Login အချိန်မှာ automatic check | ✅ Active |
| **Rate Limiting** | 6 hours တစ်ကြိမ် | ✅ Active |
| **30-Day Window** | Recent wins ကို catch လုပ်တယ် | ✅ Active |
| **Duplicate Prevention** | 3-layer protection | ✅ Active |
| **Background Execution** | UI မ block ဖြစ်ဘူး | ✅ Active |
| **Cleanup** | Automatic tracking cleanup | ✅ Active |
| **Logging** | Comprehensive debug logs | ✅ Active |

## 🎯 Best Practices Applied

1. **Single Responsibility:** Recovery service က notification recovery ကိုပဲ handle လုပ်တယ်
2. **Separation of Concerns:** Detection, recreation, tracking က separately handle လုပ်တယ်
3. **Error Handling:** Failures က gracefully handled, UI မထိခိုက်ဘူး
4. **Performance:** Efficient queries, batch processing, async execution
5. **Maintainability:** Clear code structure, comprehensive documentation
6. **Testability:** Can be tested independently with `forceCheck()`
7. **Scalability:** Rate limiting, cleanup prevent unbounded growth

---

**Last Updated:** March 23, 2026  
**Implementation Status:** ✅ Complete and Active  
**Testing Status:** Ready for QA  
**Documentation:** English + Myanmar
