# Missed Notification Recovery System

## 📋 OVERVIEW

This document describes the **Missed Notification Recovery** system that ensures users receive poll winner notifications even if they uninstalled the app before receiving the FCM push notification.

## 🚨 PROBLEM STATEMENT

### Scenario
1. User votes on a poll in the app
2. User uninstalls the app
3. Poll ends and determines winner
4. Backend credits points to `wp_twork_point_transactions` ✅
5. Backend sends FCM notification ❌ (app uninstalled, FCM token invalid)
6. User reinstalls app and logs in
7. Balance shows correctly (points were credited) ✅
8. **BUT** user never sees "You won!" notification ❌

### Impact
- Users miss the celebration moment of winning
- Users may not notice they won (if they don't check point history)
- Poor user experience and engagement

## ✅ SOLUTION: Automatic Recovery on App Launch

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    USER REINSTALLS APP                       │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              PointAuthListener (on login)                    │
│  - Loads point balance and transactions                      │
│  - Triggers MissedNotificationRecoveryService                │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│       MissedNotificationRecoveryService.check()              │
│  1. Load recent transactions (last 30 days)                  │
│  2. Filter poll winner transactions                          │
│  3. Check which ones haven't been "notified"                 │
│  4. Recreate in-app notifications for missed wins            │
│  5. Mark transactions as "notified"                          │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│           InAppNotificationProvider.refresh()                │
│  - Updates UI with new notifications                         │
│  - User sees "You won!" notification in notification center  │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 IMPLEMENTATION

### 1. Core Service: `MissedNotificationRecoveryService`

**Location:** `lib/services/missed_notification_recovery_service.dart`

**Key Methods:**

#### `checkAndRecoverMissedNotifications(userId, {forceCheck})`
- Called on app launch/login
- Rate limited: once per 6 hours (unless `forceCheck=true`)
- Loads transactions from last 30 days
- Identifies unseen poll wins
- Recreates in-app notifications
- Returns count of recovered notifications

#### `markTransactionAsNotified(userId, transactionId)`
- Tracks which transactions have been notified
- Called by `PushNotificationService` when FCM is received
- Prevents duplicate recovery for same transaction

#### `clearTrackingForUser(userId)`
- Clears notification tracking on logout
- Ensures clean state for account switching

### 2. Integration Points

#### **PointAuthListener** (`lib/widgets/point_auth_listener.dart`)
```dart
// After user authenticates and balance loads
await MissedNotificationRecoveryService.checkAndRecoverMissedNotifications(userId);
```

#### **PushNotificationService** (`lib/services/push_notification_service.dart`)
```dart
// After FCM notification is processed
if (transactionId.isNotEmpty) {
  MissedNotificationRecoveryService.markTransactionAsNotified(userId, transactionId);
}
```

#### **AuthProvider** (`lib/providers/auth_provider.dart`)
```dart
// On logout
MissedNotificationRecoveryService.clearTrackingForUser(userId);
```

## 🔍 DETECTION LOGIC

### How to Identify Poll Winner Transactions

A transaction is identified as a "poll winner" if ALL criteria match:

1. **Type:** `earn` (winners earn points)
2. **Status:** `approved` (transaction is finalized)
3. **Order ID Pattern:** Starts with `"engagement:poll:"`
4. **Description:** Contains `"winner"` or `"Poll winner reward"`

### Example Transactions

**Poll Winner (DETECTED):**
```json
{
  "id": "12345",
  "type": "earn",
  "status": "approved",
  "points": 8000,
  "order_id": "engagement:poll:789:session:abc123:uid",
  "description": "Poll winner reward: Myanmar Premier League Champion 2025 (+8000 points)",
  "created_at": "2026-03-20T10:30:00"
}
```

**Poll Entry Cost (IGNORED):**
```json
{
  "id": "12344",
  "type": "redeem",
  "points": 1000,
  "order_id": "engagement:poll_cost:789:456:xyz",
  "description": "Poll entry fee",
  "created_at": "2026-03-20T10:25:00"
}
```

## 💾 TRACKING MECHANISM

### Storage: SharedPreferences

**Keys:**
- `missed_notification_last_check_{userId}`: ISO8601 timestamp of last check
- `notified_transaction_ids_{userId}`: List of transaction IDs that have been notified

**Example:**
```
missed_notification_last_check_123 = "2026-03-23T14:30:00.000Z"
notified_transaction_ids_123 = ["12345", "12346", "12347", ...]
```

### Rate Limiting
- Check runs once per **6 hours** per user (configurable)
- Prevents excessive API calls on frequent app restarts
- Can be bypassed with `forceCheck: true` for testing

### List Pruning
- Keeps only most recent **100** transaction IDs
- Older IDs are automatically removed
- Prevents unbounded memory growth

## 🎯 USER EXPERIENCE

### Timeline Example

**Day 1 (Monday):**
- 10:00 AM: User votes on "Who will win the championship?" poll
- 10:30 AM: User uninstalls app (clears local storage)
- 11:00 AM: Poll ends, backend determines winner
- 11:00 AM: Backend credits 8000 points to database ✅
- 11:00 AM: Backend sends FCM notification ❌ (app uninstalled)

**Day 2 (Tuesday):**
- 2:00 PM: User reinstalls app and logs in
- 2:00 PM: `PointAuthListener` loads balance → 8000 points shows ✅
- 2:00 PM: Recovery service checks recent transactions
- 2:00 PM: Finds poll winner transaction from yesterday
- 2:00 PM: **Recreates notification:** "Congratulations! You're the Winner! 🏆"
- 2:00 PM: User sees notification in notification center ✅
- 2:00 PM: User taps notification → navigates to point history

**Result:** User knows they won, even 26 hours later! 🎉

## 🔄 DUPLICATE PREVENTION

### Multi-Layer Protection

1. **Transaction ID Tracking:**
   - Each notified transaction ID is stored
   - Recovery skips already-notified transactions

2. **InAppNotificationService Deduplication:**
   - Checks for same `transactionId` within last 5 minutes
   - Prevents duplicate notifications from multiple sources

3. **PointNotificationManager Deduplication:**
   - Uses notification keys (type + transaction ID + user ID)
   - Ensures single notification per event

### Edge Cases Handled

**Case 1: FCM arrives before recovery runs**
- FCM marks transaction as notified
- Recovery skips this transaction
- **Result:** Single notification ✅

**Case 2: Recovery runs before FCM arrives**
- Recovery creates notification + marks as notified
- FCM arrives → duplicate prevented by `transactionId` check
- **Result:** Single notification ✅

**Case 3: User sees popup in app (not uninstalled)**
- Popup creates notification (no transaction ID available)
- FCM arrives → creates notification with transaction ID
- Recovery might try to recreate → duplicate prevented by `transactionId` check
- **Result:** May have 2 notifications (popup + FCM), but recovery won't add 3rd ✅

**Case 4: Multiple logins within 6 hours**
- First login: recovery runs, recreates notifications
- Second login (3 hours later): recovery rate-limited, skips
- **Result:** Notifications not duplicated ✅

## 🧪 TESTING

### Manual Test Scenarios

#### Test 1: App Uninstalled During Poll
```bash
1. Login to app
2. Vote on active poll
3. Uninstall app (or clear app data)
4. Wait for poll to end (or manually trigger on backend)
5. Verify points credited in database
6. Reinstall app and login
7. ✅ Should see winner notification in notification center
```

#### Test 2: Multiple Missed Wins
```bash
1. Vote on 3 different polls
2. Uninstall app
3. All 3 polls end, all 3 win
4. Backend credits points for all 3
5. Reinstall and login
6. ✅ Should see 3 winner notifications
```

#### Test 3: Duplicate Prevention
```bash
1. Vote on poll, win (FCM works)
2. Logout and login again within 30 days
3. ✅ Should NOT see duplicate notification
```

### Debug Logging

Enable debug mode to see detailed logs:

```dart
// In main.dart or app initialization
Logger.setLogLevel(LogLevel.debug);
```

Look for these log messages:
- `Checking for missed poll winner notifications`
- `Found X missed poll winner notification(s)`
- `Recreated notification for missed poll win: {txn_id}`
- `Transaction marked as notified: {txn_id}`
- `Skipping missed notification check (last checked X hours ago)`

### Force Recovery Check (for testing)

```dart
// Trigger recovery manually (bypasses rate limiting)
final count = await MissedNotificationRecoveryService.forceCheck(userId);
print('Recovered $count missed notifications');
```

## 📊 MONITORING

### Metrics to Track

1. **Recovery Success Rate:**
   - How many missed notifications are successfully recovered
   - Check logs for "Recreated notification for missed poll win"

2. **False Positives:**
   - Notifications that were already seen but recreated
   - Check for duplicate complaints from users

3. **API Performance:**
   - Time taken to load and process transactions
   - Typical: < 2 seconds for 30 days of transactions

### Database Queries

**Check recent poll winner transactions:**
```sql
SELECT * FROM wp_twork_point_transactions
WHERE user_id = {USER_ID}
  AND type = 'earn'
  AND status = 'approved'
  AND order_id LIKE 'engagement:poll:%'
  AND description LIKE '%winner%'
  AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY created_at DESC;
```

**Check if notification was sent via FCM:**
```sql
-- This depends on FCM logging implementation
-- Check FCM notification logs or Firebase Console
```

## 🎯 BEST PRACTICES

### DO ✅
- Run recovery check on every login (rate-limited automatically)
- Keep transaction ID tracking list pruned (< 100 entries)
- Log recovery events for monitoring
- Handle recovery failures gracefully (don't block login)

### DON'T ❌
- Don't recreate notifications for poll entry costs (only wins)
- Don't check transactions older than 30 days (old news)
- Don't block UI while recovery runs (async background)
- Don't create duplicate notifications (rely on built-in prevention)

## 🔮 FUTURE ENHANCEMENTS

1. **Backend API Enhancement:**
   - Add `transaction_id` to poll results API response
   - Enables immediate marking as notified when popup shows

2. **Smart Recovery Window:**
   - Adjust 30-day window based on user engagement patterns
   - More active users = shorter window

3. **Batch Notification Display:**
   - If user has 5+ missed wins, show summary notification
   - "You won 5 polls while you were away! Total: 40,000 PNP"

4. **Recovery Analytics:**
   - Track recovery rate, timing, and success
   - Identify users with frequent FCM failures

## 🆘 TROUBLESHOOTING

### Issue: Notifications not recovering

**Check:**
1. Is `PointAuthListener` properly integrated in app widget tree?
2. Are transactions actually in database? (Check via SQL query)
3. Is rate limiting blocking recovery? (Check last_check timestamp)
4. Are logs showing recovery attempt?

**Debug:**
```dart
// Force recovery with detailed logging
Logger.setLogLevel(LogLevel.debug);
final count = await MissedNotificationRecoveryService.forceCheck(userId);
```

### Issue: Duplicate notifications

**Check:**
1. Are transaction IDs being properly tracked?
2. Is `markTransactionAsNotified` being called?
3. Is duplicate prevention in `InAppNotificationService` working?

**Fix:**
```dart
// Clear notification tracking and re-sync
await MissedNotificationRecoveryService.clearTrackingForUser(userId);
await MissedNotificationRecoveryService.forceCheck(userId);
```

### Issue: Old wins being recreated

**Reason:** 30-day window is intentional to catch recent wins.

**Solution:** If user complains about old notifications:
- Reduce window to 7 days in `checkAndRecoverMissedNotifications`
- Or add user preference for notification recovery

## 📝 TECHNICAL NOTES

### Why 30 Days?
- Balance between catching recent wins and avoiding old news
- Most users reinstall within days, not weeks
- Keeps API load reasonable (< 1000 transactions typically)

### Why 6-Hour Rate Limit?
- Prevents excessive checks on frequent app restarts
- Long enough to avoid API spam
- Short enough to catch new wins within reasonable time

### Why Track by Transaction ID?
- Transaction IDs are unique and immutable
- Works across app reinstalls (stored in SharedPreferences)
- More reliable than timestamp-based deduplication

### Why Not Store in Database?
- SharedPreferences is sufficient for client-side tracking
- No backend changes required
- Automatically cleared on app uninstall (fresh start)

## 🎓 PROFESSIONAL INSIGHTS

### Design Principles Applied

1. **Idempotency:** Recovery can run multiple times safely
2. **Defensive Programming:** Handles missing data, API failures gracefully
3. **Performance:** Rate-limited, batch processing, async execution
4. **UX First:** Non-blocking, background recovery, immediate UI updates
5. **Maintainability:** Clear separation of concerns, comprehensive logging

### Trade-offs

| Aspect | Choice | Alternative | Why This Choice |
|--------|--------|-------------|-----------------|
| **Storage** | SharedPreferences | Backend database | Simpler, no backend changes needed |
| **Window** | 30 days | 7 days / 90 days | Balance recency vs catching delayed reinstalls |
| **Rate Limit** | 6 hours | 1 hour / 24 hours | Responsive without API spam |
| **Detection** | Pattern matching | Backend flag | Works with existing schema |

### Security Considerations

- **User ID Validation:** Only recover for authenticated user
- **Transaction Ownership:** Transactions already filtered by user_id in API
- **No Sensitive Data:** Notification content is same as original FCM
- **Rate Limiting:** Prevents abuse/DoS from malicious apps

## 📚 RELATED DOCUMENTATION

- [`POLL_POINTS_FLOW_ANALYSIS.md`](./POLL_POINTS_FLOW_ANALYSIS.md) - Overall poll points flow
- [`POINT_MANAGEMENT_REALTIME_NOTIFICATIONS_GUIDE.md`](../POINT_MANAGEMENT_REALTIME_NOTIFICATIONS_GUIDE.md) - Notification architecture
- [`README_POINTS_SYSTEM.md`](../README_POINTS_SYSTEM.md) - Points system overview

## 🏆 BENEFITS

1. **Improved User Experience:** Users never miss winning moments
2. **Increased Engagement:** Winner notifications drive return engagement
3. **Data Integrity:** Points and notifications always in sync
4. **Reliability:** Works even with FCM failures
5. **Zero Backend Changes:** Pure frontend solution

---

**Last Updated:** March 23, 2026  
**Author:** T-Commerce Development Team  
**Status:** ✅ Implemented and Active
