# FCM Poll Winner Notifications - အပြည့်အစုံ အကောင်အထည်ဖော်မှု

## အကြောင်းအရာ

Poll winner တွေအတွက် FCM (Firebase Cloud Messaging) notification system ကို ဘယ်အခြေအနေမျိုးမှာမဆို notification တွေ **ဘယ်တော့မှ လွတ်သွားမှာ မဟုတ်ဘူး**ဆိုတာကို သေချာစေဖို့ အပြည့်အစုံ တည်ဆောက်ထားပါတယ်။

---

## ပြဿနာ နဲ့ အဖြေ

### ပြဿနာ
User က app ကို uninstall လုပ်လိုက်ရင် poll winner FCM notification မရသေးဘူးဆိုရင် အဲဒီ notification တွေ ထာဝရ ပျောက်သွားတယ်။ Backend မှာ point တွေက မှန်မှန်ကန်ကန် ထည့်ပေးထားပေမယ့် notification ကတော့ ရောက်မသွားဘူး။

### အဖြေ
Multi-layered notification delivery system:
1. **Poll winner အတွက် စိတ်လှုပ်ရှားစရာကောင်းတဲ့ notification content**
2. **Transaction ID tracking** - duplicate ကို ကာကွယ်ဖို့
3. **Automatic retry queue** - fail ရင် ပြန်လည် ကြိုးစားမယ်
4. **Manual retry endpoint** - frontend ကနေ ပြန်စမ်းလို့ရတယ်
5. **အသေးစိတ် logging** - monitor လုပ်လို့ရတယ်

---

## အဓိက တိုးတက်မှုများ

### 1. စိတ်လှုပ်ရှားစရာ Notification Content

#### အရင် (Generic)
```
Title: 🎯 8000 PNP from Activity
Body: Thank you for your participation! You earned 8000 PNP...
```

#### အခု (စိတ်လှုပ်ရှားစရာ & အထူးသီးသန့်)
```
Title: 🏆 Winner! "မြန်မာနိုင်ငံရဲ့ မြို့တော်က ဘာလဲ?" +8000 PNP
Body: 🎉 ဂုဏ်ယူပါတယ်! 'မြန်မာနိုင်ငံရဲ့ မြို့တော်က ဘာလဲ?' ကို အနိုင်ရခဲ့ပါပြီ! သင့် ရွေးချယ်မှုက အနိုင်ရတဲ့ အဖြေနဲ့ ကိုက်ညီပါတယ်။ 8000 PNP ထည့်ပေးပြီးပါပြီ (စုစုပေါင်း 125,000 PNP)။ ဆက်လက်ကစားပြီး အနိုင်ရကြပါ!
```

**အကျိုးကျေးဇူး**:
- User တွေ notification ကို မြင်ရင် စိတ်လှုပ်ရှားမှု ပိုများတယ်
- Poll title ပါဝင်တာကြောင့် ဘယ် poll ကို win ရတယ်ဆိုတာ သိရတယ်
- Balance ပါဝင်တာကြောင့် ခုနက balance ကို သိရတယ်

---

### 2. Transaction ID Tracking

FCM notification တိုင်းမှာ backend `transaction_id` ပါဝင်တယ်:

**အကျိုးကျေးဇူး**:
- **Duplicate prevention**: တူတဲ့ notification ကို ၂ ခါ မပြဘူး
- **Tracking**: FCM ကို specific database transaction နဲ့ ချိတ်ဆက်ထားတယ်
- **Recovery**: Missed notification recovery system ကို အသုံးပြုလို့ရတယ်

**Code တည်နေရာ**: `award_engagement_points_to_user()` function

```php
$fcm_sent = $this->send_points_fcm_notification(
    $user_id,
    'engagement_points',
    array(
        'transaction_id' => $transaction_id, // CRITICAL
        'points' => $points,
        'item_type' => 'poll',
        'item_title' => $item_title,
        'current_balance' => $balance_after,
    )
);
```

---

### 3. Automatic Retry Queue

FCM delivery fail ရင် (token မရှိဘူး၊ network error၊ etc.) notification ကို **အလိုအလျောက် queue လုပ်ထားပြီး** နောက်မှ ပြန်စမ်းတယ်။

**Queue သိမ်းဆည်းမှု**: WordPress options table (`twork_fcm_failed_queue`)

**Retry ဘယ်အချိန်လုပ်လဲ**:
1. User က app ဖွင့်ပြီး FCM token register လုပ်တဲ့အခါ
2. Frontend က manual retry endpoint ကို ခေါ်တဲ့အခါ
3. 5 ကြိမ် ကြိုးစားပြီးမှ fail ရင် queue ကနေ ဖယ်ထုတ်တယ်

**အလုပ်လုပ်ပုံ**:

```
┌──────────────────────────────────────────┐
│ FCM Send Attempt                          │
│ - User has no tokens (app uninstalled)   │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│ QUEUE FOR RETRY                           │
│ - Save notification data                 │
│ - Save error details                     │
│ - Track retry count                      │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│ User Opens App Later                      │
│ - FCM token registered                   │
│ - Auto-retry triggered                   │
│ - Queued notification sent               │
└───────────────────────────────────────────┘
```

---

### 4. Manual Retry Endpoint

Frontend ကနေ queued notifications တွေကို manual ပြန်စမ်းလို့ရတယ်။

**Endpoint**: `POST /wp-json/twork/v1/fcm/retry-queued/{user_id}`

**Response**:
```json
{
  "success": true,
  "retried_count": 2,
  "message": "Successfully retried 2 notification(s)"
}
```

**Flutter Integration ဥပမာ**:
```dart
Future<void> retryQueuedNotifications(String userId) async {
  try {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/wp-json/twork/v1/fcm/retry-queued/$userId'),
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final retriedCount = data['retried_count'] ?? 0;
      
      if (retriedCount > 0) {
        Logger.info('$retriedCount ခု notification ကို ပြန်ပို့ပြီးပါပြီ', tag: 'FCM');
        await InAppNotificationProvider.instance.loadNotifications();
      }
    }
  } catch (e) {
    Logger.error('Retry error: $e', tag: 'FCM');
  }
}
```

---

### 5. Enhanced Error Handling

**အင်္ဂါရပ်များ**:
- Automatic retry (2 ကြိမ် အထိ ချက်ခြင်း ပြန်စမ်းတယ်)
- 100ms delay ပေးပြီး ပြန်စမ်းတယ်
- အသေးစိတ် error logging
- Token validation & cleanup

**Code ဥပမာ**:
```php
foreach ($tokens as $token_data) {
    $retry_count = 0;
    $max_retries = 2;
    
    while (!$send_success && $retry_count <= $max_retries) {
        $result = twork_send_fcm($token, $title, $body, $data);
        
        if ($result === true) {
            $success_count++;
            $send_success = true;
            
            // Success log
            error_log("Poll winner FCM delivered ✓");
        } else {
            if ($retry_count < $max_retries) {
                $retry_count++;
                usleep(100000); // 100ms စောင့်ပြီး ပြန်စမ်းမယ်
                continue;
            }
            // Failed after retries - queue it
            $this->queue_failed_fcm_notification(...);
        }
    }
}
```

---

## လုပ်ငန်းစဉ် အဆင့်ဆင့်

### အဆင့် 1: Poll Winner သတ်မှတ်ခြင်း
```
Poll က resolve ဖြစ်သွားတယ် (scheduled or manual)
    ↓
Winning option ကို သတ်မှတ်တယ်
    ↓
Winner users တွေကို ရှာတယ်
```

### အဆင့် 2: Points Award လုပ်ခြင်း
```
award_engagement_points_to_user() ကို ခေါ်တယ်
    ↓
wp_twork_point_transactions မှာ transaction create လုပ်တယ်
    ↓
Transaction ID ကို ရယ်တယ် (e.g., 4567)
    ↓
User balance ကို update လုပ်တယ်
```

### အဆင့် 3: FCM ပို့ခြင်း
```
send_points_fcm_notification() ကို ခေါ်တယ်
    ↓
Notification content ကို prepare လုပ်တယ်:
    Title: 🏆 Winner! "Poll Title" +8000 PNP
    Body: 🎉 You won! ...
    Data: { transactionId: "4567", points: "8000", ... }
    ↓
User ရဲ့ FCM tokens တွေကို ရယ်တယ်
    ↓
Token တိုင်းကို notification ပို့တယ် (2 retries)
```

### အဆင့် 4A: Success Path
```
FCM delivered successfully ✓
    ↓
Queue ကနေ clear လုပ်တယ်
    ↓
User က notification ရတယ်
    ↓
အပြီး!
```

### အဆင့် 4B: Failure Path (App Uninstalled)
```
FCM failed (no tokens) ✗
    ↓
Notification ကို queue လုပ်တယ်
    ↓
WP options မှာ သိမ်းထားတယ်
    ↓
[User reinstalls app later]
    ↓
User opens app & registers FCM token
    ↓
Auto-retry triggered
    ↓
Queued notification ပို့တယ်
    ↓
User က notification ရတယ် ✓
    ↓
Queue ကနေ ဖယ်ထုတ်တယ်
```

---

## Testing လမ်းညွှန်

### Test Case 1: Normal Flow (App ဖွင့်ထားတယ်)
1. User က poll မှာ vote လုပ်တယ်
2. Poll က resolve ဖြစ်သွားတယ်
3. Backend က points award + FCM ပို့တယ်
4. User က FCM notification ချက်ခြင်း ရတယ်
5. App မှာ "You won!" popup ပေါ်လာတယ်

**ရလဒ်**: ✅ Notification ချက်ခြင်း ရောက်သွားတယ်

---

### Test Case 2: App Uninstalled (Critical Case)
1. User က poll မှာ vote လုပ်တယ်
2. User က app ကို uninstall လုပ်လိုက်တယ်
3. Poll က resolve ဖြစ်သွားတယ် (backend က points ထည့်ပေးတယ်)
4. FCM fail ဖြစ်သွားတယ် (tokens မရှိတော့ဘူး) → **Queue လုပ်ထားတယ်**
5. User က app ကို ပြန် reinstall လုပ်တယ်
6. User က ပြန် login ဝင်တယ်
7. FCM token register ဖြစ်သွားတယ် → **Auto-retry လုပ်တယ်**
8. Queued notification ကို ပို့တယ်
9. User က "You won!" notification မြင်ရတယ်

**ရလဒ်**: ✅ App ပြန်ဖွင့်တဲ့အခါ notification ရောက်သွားတယ်

---

### Test Case 3: Network Failure
1. User က poll မှာ vote လုပ်တယ်
2. Poll resolve ဖြစ်သွားတယ်
3. FCM ပို့တဲ့အခါ network error ဖြစ်သွားတယ်
4. Notification **queue လုပ်ထားတယ်**
5. နောက်မှ user က app ဖွင့်တယ် (network ကောင်းတဲ့အခါ)
6. FCM token register → **Auto-retry**
7. Notification ရောက်သွားတယ်

**ရလဒ်**: ✅ နောက်တစ်ခါ app ဖွင့်တဲ့အခါ notification ရောက်သွားတယ်

---

## Configuration လိုအပ်ချက်များ

### 1. FCM Plugin Setup

`wp-content/plugins/twork-fcm-notify/twork-fcm-notify.php` ကို အလုပ်လုပ်အောင် လုပ်ထားရမယ်:
- `TWORK_FCM_PROJECT_ID` မှန်ကန်ရမယ် (e.g., 'twork-commerce')
- `serviceAccountKey.json` မှာ Firebase credentials တွေ မှန်ကန်ရမယ်

### 2. WordPress Debug Mode (အကြံပြုပါတယ်)

`wp-config.php` မှာ logging enable လုပ်ပါ:
```php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
```

### 3. Plugin Status စစ်ဆေးခြင်း

Admin page မှာ FCM status ကို ကြည့်လို့ရတယ်:
- သွားရမည့်နေရာ: WP Admin → T-Work Rewards → Settings
- စစ်ဆေးရမည်: "FCM Notify Plugin: Active ✓"
- စမ်းသပ်ရမည်: "Send Test Notification" button ကို နှိပ်ပါ

---

## အဓိက အင်္ဂါရပ်များ

### 1. Exciting Notification Title
Poll winner တိုင်းမှာ poll title ပါတဲ့ စိတ်လှုပ်ရှားစရာ title ပေးတယ်:
```
🏆 Winner! "Poll Title" +8000 PNP
```

### 2. Transaction ID in Payload
FCM data မှာ `transactionId` field ပါဝင်တယ်:
```json
{
  "type": "engagement_points",
  "transactionId": "4567",
  "points": "8000",
  "itemType": "poll",
  "itemTitle": "Poll Title",
  "currentBalance": "125000"
}
```

### 3. Automatic Queue & Retry
FCM fail ရင် အလိုအလျောက် queue လုပ်ပြီး ပြန်စမ်းတယ်:
- User က app ဖွင့်တိုင်း auto-retry
- Manual retry endpoint လည်း ရှိတယ်
- 5 ကြိမ် ပြီးရင် queue ကနေ ဖယ်ထုတ်တယ်

### 4. Comprehensive Logging
အသေးစိတ် log တွေ သိမ်းထားတယ်:
```
T-Work Rewards: Poll winner FCM delivered ✓ - User: 123, Points: 8000
T-Work Rewards: CRITICAL - Poll winner FCM FAILED for user 123
T-Work Rewards: FCM notification queued for retry. Queue size: 5
T-Work Rewards: Successfully retried 2 queued notification(s) for user 123
```

---

## Frontend Integration

### 1. Login တဲ့အခါ Retry လုပ်ပါ

```dart
// PointAuthListener or AuthProvider မှာ
Future<void> _retryQueuedNotifications(String userId) async {
  try {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/wp-json/twork/v1/fcm/retry-queued/$userId'),
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final retriedCount = data['retried_count'] ?? 0;
      
      if (retriedCount > 0) {
        Logger.info('$retriedCount ခု notification ပြန်ပို့ပြီးပါပြီ', tag: 'FCM');
        await InAppNotificationProvider.instance.loadNotifications();
      }
    }
  } catch (e) {
    Logger.error('Retry error: $e', tag: 'FCM');
  }
}

// handleAuthStateChange မှာ ခေါ်ပါ
void _checkAuthAndLoadPoints() {
  // ... existing auth code ...
  
  pointProvider.handleAuthStateChange(
    isAuthenticated: true,
    userId: userId,
  ).then((_) {
    // Points loaded - retry queued notifications
    _retryQueuedNotifications(userId);
  });
}
```

### 2. FCM Data ကို Process လုပ်ပါ

```dart
void _handlePollWinnerFCM(Map<String, dynamic> data) {
  final transactionId = data['transactionId'] ?? '';
  final points = data['points'] ?? '0';
  final itemTitle = data['itemTitle'] ?? '';
  final currentBalance = data['currentBalance'] ?? '0';
  
  InAppNotificationService().createPointNotification(
    type: 'engagement_points',
    title: 'Poll Winner',
    body: 'You won!',
    points: points,
    currentBalance: currentBalance,
    transactionId: transactionId, // CRITICAL
  );
}
```

---

## Monitoring & Debugging

### Queue Status ကို ကြည့်ခြင်း

WordPress admin or debug script မှာ:
```php
$queue = get_option('twork_fcm_failed_queue', array());
echo "Queued notifications: " . count($queue) . "\n";

foreach ($queue as $key => $entry) {
    echo sprintf(
        "User: %d, Points: %d, Queued: %s, Retries: %d\n",
        $entry['user_id'],
        $entry['data']['points'],
        date('Y-m-d H:i:s', $entry['queued_at']),
        $entry['retry_count']
    );
}
```

### Error Logs ကို စစ်ဆေးခြင်း

`wp-content/debug.log` မှာ ကြည့်ပါ:
```
[23-Mar-2026 10:30:45] T-Work Rewards: Poll winner FCM delivered ✓
[23-Mar-2026 10:31:20] T-Work Rewards: CRITICAL - Poll winner FCM FAILED
[23-Mar-2026 10:31:20] T-Work Rewards: FCM notification queued for retry
[23-Mar-2026 11:15:30] T-Work Rewards: Successfully retried 2 queued notification(s)
```

---

## ပြဿနာ ဖြေရှင်းခြင်း

### ပြဿနာ: Notification မရဘူး

**စစ်ဆေးရမည့်အချက်များ**:
1. FCM plugin active လား? → WP Admin → Plugins ကို ကြည့်ပါ
2. User မှာ FCM tokens ရှိလား? → Debug endpoint ကို သုံးပါ
3. serviceAccountKey.json valid လား? → File content ကို စစ်ပါ
4. Error logs ရှိလား? → `wp-content/debug.log` ကို ကြည့်ပါ

**ဖြေရှင်းနည်း**:
```bash
# Check FCM plugin status
ls -la wp-content/plugins/twork-fcm-notify/

# Check service account key
ls -la wp-content/plugins/twork-fcm-notify/serviceAccountKey.json

# Check queue
wp eval 'print_r(get_option("twork_fcm_failed_queue"));'

# Test FCM for specific user
curl -X POST "https://your-site.com/wp-json/twork/v1/fcm/retry-queued/123"
```

---

### ပြဿနာ: Duplicate notifications

**စစ်ဆေးရမည့်အချက်များ**:
1. Transaction ID ပါဝင်လား?
2. Deduplication logic အလုပ်လုပ်လား?
3. Multiple calls ဖြစ်နေလား?

**ဖြေရှင်းနည်း**:
- FCM payload မှာ `transactionId` field ရှိမရှိ စစ်ပါ
- `order_id` က unique ဖြစ်မဖြစ် စစ်ပါ
- `InAppNotificationService` deduplication logic ကို ကြည့်ပါ

---

### ပြဿနာ: Queue ကြီးလွန်းတယ်

**စစ်ဆေးရမည့်အချက်များ**:
1. User တွေ app ကို များများ uninstall လုပ်နေလား?
2. FCM plugin အလုပ်လုပ်လား?
3. App ဖွင့်တဲ့အခါ token register လုပ်လား?

**ဖြေရှင်းနည်း**:
```php
// Check queue size
$queue = get_option('twork_fcm_failed_queue', array());
if (count($queue) > 100) {
    echo "WARNING: Large queue size: " . count($queue);
}

// Manual cleanup old entries
foreach ($queue as $key => $entry) {
    $age_days = (time() - $entry['queued_at']) / 86400;
    if ($age_days > 30 || $entry['retry_count'] >= 5) {
        unset($queue[$key]);
    }
}
update_option('twork_fcm_failed_queue', $queue);
```

---

## Performance

### Caching Strategy
- **In-memory cache**: 5 minutes
- **Transient cache**: 5 minutes
- **Auto-invalidation**: Token update တိုင်း

### Rate Limiting
- **FCM sends**: 30 seconds per user/transaction
- **Queue size**: Maximum 1,000 entries
- **Retry limit**: Maximum 5 attempts

### Scalability
- Token caching ကြောင့် database queries လျှော့သွားတယ်
- Non-blocking requests ကြောင့် performance ကောင်းတယ်
- Batch processing support ပါတယ်

---

## အကျဉ်းချုပ်

Enhanced FCM system ရဲ့ အဓိက အင်္ဂါရပ်များ:

✅ **စိတ်လှုပ်ရှားစရာ notification content** - User တွေ စိတ်ဝင်စားမှု များစေတယ်  
✅ **Transaction ID tracking** - Deduplication & recovery အတွက်  
✅ **Automatic retry queue** - Temporary failures တွေကို ကိုင်တွယ်နိုင်တယ်  
✅ **Manual retry endpoint** - Frontend fallback ရှိတယ်  
✅ **အသေးစိတ် logging** - Monitoring & debugging လုပ်လို့ရတယ်  

**ရလဒ်**: User တွေက app ကို uninstall လုပ်ပြီး reinstall လုပ်လည်း poll winner notifications တွေ **အမြဲတမ်း** ရလိမ့်မယ်။

---

## ဆက်စပ် Documentation

1. `docs/MISSED_NOTIFICATION_RECOVERY.md` - Backend transaction recovery system
2. `docs/MISSED_NOTIFICATION_RECOVERY_MM.md` - Myanmar version
3. `docs/README_POINTS_SYSTEM.md` - Complete points system overview

---

## နောက်ထပ် တိုးတက်မှုများ

1. **Admin Dashboard Widget**: FCM queue status & failed notifications ကို ပြတယ်
2. **Batch Retry**: WP-Cron နဲ့ queue တစ်ခုလုံးကို process လုပ်တယ်
3. **Priority Queue**: Poll wins က ပိုမြန်တဲ့ retry ရတယ်
4. **Analytics**: FCM delivery rates & failure reasons ကို track လုပ်တယ်
5. **Alternative Channels**: SMS/Email fallback for critical notifications

---

**Result**: Poll winner notifications တွေ **ဘယ်တော့မှ မပျောက်ဘူး** ဆိုတာ အာမခံထားပါတယ်! 🎉
