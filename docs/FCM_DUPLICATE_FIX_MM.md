# FCM Duplicate Notification Fix (Poll Winner Points)

## ပြဿနာ

Poll တစ်ခုထဲ ဆိုရင် အဆင်ပြေပါတယ်။ ဒါပေမယ့် **Poll ၂ ခု (#280, #284) ရှိတဲ့အခါ Poll #280 က Winner Point ကို ၂ ခါ ပေါင်းထည့်နေပါတယ်** (user က notification ၂ ခါ receive လုပ်နေတယ်)။

## မူလ Code ရဲ့ ပြဿနာ

`award_engagement_points_to_user()` function မှာ:

```php
// Line 7909-7953: Check duplicate order_id
$exists = $wpdb->get_var("SELECT id FROM $pt_table WHERE user_id = %d AND order_id = %s");

if (!$exists) {
    // Insert new points ✓
    $wpdb->insert($pt_table, array(...));
} else {
    // Skip insert (duplicate) ✓
    error_log('Duplicate order_id detected');
}

// Line 7982-7993: ⚠️ PROBLEM - Send FCM notification ALWAYS (duplicate or not!)
$fcm_sent = $this->send_points_fcm_notification(...);
```

**ဘာကြောင့် ဖြစ်လဲ:**
1. Poll တစ်ခုဆိုရင် `/poll/state/280` ကို တစ်ခါပဲ call တယ် → FCM တစ်ခါပဲ send တယ် → OK ✓
2. Poll ၂ ခု ရှိရင် app က poll card တိုင်းအတွက် `/poll/state` ကို call တယ်
3. Poll #280 က `SHOWING_RESULTS` state မှာ retry logic, refresh, concurrent requests စတာတွေ ကြောင့် multiple times process ဖြစ်နိုင်တယ်
4. Order ID က points duplicate ကို prevent လုပ်ပေမယ့် **FCM notification က အမြဲ send နေတယ်** → User က notification ၂ ခါ receive လုပ်တယ်

## ပြင်ဆင်ချက်

**FCM notification ကို row အသစ် insert လုပ်မှပဲ send ပါမယ်:**

```php
// Track if this is a NEW transaction
$is_new_transaction = false;

if (!$exists) {
    $insert_result = $wpdb->insert($pt_table, array(...));
    if ($insert_result !== false) {
        $transaction_id = (int) $wpdb->insert_id;
        $is_new_transaction = true; // ✓ Mark as new
    }
} else {
    // Duplicate order_id — skip insert AND FCM
    error_log('Duplicate order_id detected — skipping insert AND FCM');
}

// Send FCM ONLY for NEW transactions
if ($is_new_transaction && $transaction_id > 0) {
    $fcm_sent = $this->send_points_fcm_notification(...);
    error_log('Poll winner FCM notification SENT ✓');
} else if (!$is_new_transaction) {
    error_log('Duplicate award call — FCM notification SKIPPED to prevent spam');
}
```

## ရလဒ်

### အရင် (Before Fix)
- Poll #280: Call 1st time → Points +8000 ✓, FCM send ✓
- Poll #280: Call 2nd time → Points skip ✓, **FCM send ✗ (duplicate!)**
- User က notification ၂ ခါ မြင်တယ်

### အခု (After Fix)
- Poll #280: Call 1st time → Points +8000 ✓, FCM send ✓
- Poll #280: Call 2nd time → Points skip ✓, **FCM skip ✓ (correct!)**
- User က notification တစ်ခါပဲ မြင်တော့မယ်

## Benefits

✅ **Idempotent FCM**: Duplicate calls ဖြစ်လည်း notification တစ်ခါပဲ send တယ်  
✅ **No notification spam**: User က same winner notification ထပ်ခါထပ်ခါ မရတော့ဘူး  
✅ **Backend consistency**: Points awarding နဲ့ FCM sending က synchronized ဖြစ်တယ်  
✅ **Clean logs**: Duplicate calls ကို ရှင်းရှင်းလင်းလင်း log လုပ်ထားတယ်

## Testing

1. **Create 2 AUTO_RUN polls**: Poll #280 and Poll #284
2. **Vote and wait for results**: Wait until both polls show `SHOWING_RESULTS`
3. **Refresh app multiple times**: Open/close app, scroll feed
4. **Check WP_DEBUG logs**:
   ```
   T-Work Rewards: Direct insert SUCCESS. ID: 12345, User: 123, Points: +8000
   T-Work Rewards: Poll winner FCM notification SENT ✓
   
   [On 2nd call with same order_id]
   T-Work Rewards: Duplicate order_id detected — skipping insert AND FCM
   T-Work Rewards: Duplicate award call — FCM notification SKIPPED to prevent spam
   ```
5. **Verify user receives exactly 1 notification** per poll win

## Modified File

- `UPLOAD_TO_SERVER/twork-rewards-system.php` (lines 7908-8006)
- Synced to `wp-content/plugins/twork-rewards-system/twork-rewards-system.php`

---

**ပြင်ဆင်ရက်စွဲ:** 2026-03-23  
**Fix by:** Senior Developer (Deep Dive Analysis)
