# 🎯 MANUAL_SESSION Poll Mode အသုံးပြုနည်း (မြန်မာ)

## 📌 ပြဿနာနဲ့ ဖြေရှင်းချက်

### ပြဿနာ:
```
AUTO_RUN Poll → အလိုအလျောက် random winner ရွေး
                ↓
            Winner အများကြီး ဖြစ်နေတယ်
                ↓
            Admin က ထိန်းချုပ်လို့ မရဘူး ❌
```

### ဖြေရှင်းချက်:
```
MANUAL_SESSION Mode → Admin က session တိုင်းမှာ winner ရွေး
                      ↓
                  User တွေ အကြိမ်ကြိမ် vote လုပ်လို့ရတယ် ✅
                      ↓
                  Admin က winner ထိန်းချုပ်ရတယ် ✅
                      ↓
                  Result ကို instant (သို့) scheduled ပြလို့ရတယ် ✅
```

---

## 🔄 Poll Mode အမျိုးအစားများ

| Mode | User က ဘယ်လောက် vote လုပ်လို့ရလဲ | Winner ဘယ်သူရွေးလဲ | Result ဘယ်အချိန်ပြလဲ |
|------|------------------------------|-------------------|---------------------|
| **AUTO_RUN** | အကြိမ်ကြိမ် (session တိုင်း) | 🤖 System random | ⏰ Auto (timer) |
| **MANUAL_SESSION** | အကြိမ်ကြိမ် (session တိုင်း) | 👤 Admin ရွေး | ⚙️ Instant OR Scheduled |
| **MANUAL** | တစ်ခါတည်း | 👤 Admin ရွေး | ⚡ Instant |

---

## 🔧 AUTO_RUN ကနေ MANUAL_SESSION ပြောင်းနည်း

### အဆင့် 1: WordPress Admin မှာ ပြောင်းရန်

1. **T-Work Rewards → Engagement Items** ဝင်ပါ
2. Poll ကို **Edit** နှိပ်ပါ
3. **Poll Mode** dropdown မှာ:
   - ရှေးက: `Auto Run – Period-based, auto-close, random winner`
   - အခု: **`Manual Session – Period-based voting, admin picks winner`** ရွေးပါ
4. Timer settings ကို **မပြောင်းပါနဲ့**:
   ```
   Poll Duration: 2 မိနစ် (ရှိသလို ထားပါ)
   Result Display: 1 မိနစ် (ရှိသလို ထားပါ)
   ```
5. **Update Item** နှိပ်ပါ

### အဆင့် 2: File Upload လုပ်ရန်

```bash
# Backend PHP files ၂ ခု upload လုပ်ပါ:
wp-content/plugins/twork-rewards-system/twork-rewards-system.php
wp-content/plugins/twork-rewards-system/includes/class-poll-auto-run.php

# Frontend Dart file:
lib/widgets/engagement_carousel.dart
```

### အဆင့် 3: App Restart

```bash
# Development:
flutter run  # နောက်ပြီး 'r' နှိပ်ပါ (hot restart)

# Production:
# App ကို ပြန် build ပြီး publish လုပ်ရမယ်
```

---

## 👨‍💼 Admin ဘယ်လို Winner ရွေးမလဲ

### Resolve UI သို့ သွားရန်:

1. **T-Work Rewards → Engagement Items**
2. Poll ကို **View Results** နှိပ်ပါ
3. Voting ပိုင်း ပြီးပြီဆိုရင် အပြာရောင် card မြင်ရမယ်:

```
┌──────────────────────────────────────────┐
│ 🏆 Resolve Poll – Set Correct Answer    │
│                        [Session: s5]     │
├──────────────────────────────────────────┤
│ 📌 Manual Session Mode:                  │
│ Session s5 ကို resolve လုပ်နေပါတယ်။    │
│ Winner တွေကို points ပေးမှာပါ။          │
├──────────────────────────────────────────┤
│ ✅ Option ရွေးပါ:                        │
│ [Dropdown: Tiger / Dragon / ...]        │
│                                          │
│ ✅ Result ပြချိန်:                       │
│ ○ Instant – ချက်ချင်း ပြပါ             │
│ ○ Scheduled – Timer ပြည့်မှ ပြပါ       │
│                                          │
│ [Set Winner & Award Points]             │
└──────────────────────────────────────────┘
```

### ဥပမာ: Session 5 ကို Resolve လုပ်ခြင်း

#### Option A: Instant Display (ချက်ချင်း ပြမယ်)

```
1. Admin action:
   - Winner: Tiger ရွေးပါ
   - Display: "Instant" ရွေးပါ
   - Click: "Set Winner & Award Points"

2. System response (ချက်ချင်း):
   ✅ Tiger voters ကို points ပေးလိုက်တယ်
   ✅ App မှာ result ထွက်လာတယ် (ချက်ချင်း)
   ✅ Notification ပို့လိုက်တယ်
   ⏰ 1 မိနစ် နောက်: Session 6 စတယ်
```

#### Option B: Scheduled Display (Timer ပြည့်မှ ပြမယ်)

```
1. Admin action:
   - Winner: Dragon ရွေးပါ
   - Display: "Scheduled" ရွေးပါ
   - Click: "Set Winner & Award Points"

2. System response (တဖြည်းဖြည်း):
   ✅ Dragon voters ကို points ပေးပြီးပြီ (backend)
   ⏰ App မှာ result ကို 2 မိနစ် အပြည့်မှာ ပြမယ်
   ✅ Notification ပို့ပြီးပြီ
   ⏰ 1 မိနစ် နောက်: Session 6 စတယ်
```

---

## 🎮 User Experience (App မှာ ဘာမြင်ရမလဲ)

### Session 5: Voting Active
```
┌────────────────────────┐
│ 🔥 4X Win Poll         │
│ Tiger vs Dragon        │
│ Select: [☑️ Tiger]      │
│ Amount: [2000 PNP]     │
│ ⏱️ 01:30 remaining      │
│ [Submit] (2000 PNP)    │
└────────────────────────┘
```

### Session 5: Voting Closed (Admin မရွေးသေးဘူး)
```
┌────────────────────────┐
│ 🔥 4X Win Poll         │
│ ✅ Vote လုပ်ပြီးပါပြီ    │
│ Your choice: Tiger     │
│ ⏳ Waiting...          │
│ (Admin မှာ ရှိနေပါပြီ) │
└────────────────────────┘
```

### Session 5: Admin Resolved (Instant)
```
┌────────────────────────┐
│ 🔥 4X Win Poll         │
│ 🏆 Winner: TIGER! 🐯   │
│ You won: +8,000 PNP 🎉 │
│ Balance: 45,000 PNP    │
│ Votes: 🐯 67% | 🐉 33% │
│ ⏱️ Next vote: 00:45     │
└────────────────────────┘
```

### Session 6: New Voting Opens
```
┌────────────────────────┐
│ 🔥 4X Win Poll         │
│ Tiger vs Dragon        │
│ Select: [ Tiger]       │ ← ပြန် vote လုပ်လို့ရပြီ!
│ Amount: [3000 PNP]     │
│ ⏱️ 02:00 remaining      │
│ [Submit] (3000 PNP)    │
└────────────────────────┘
```

---

## 🧪 Test လုပ်ကြည့်ရန်

### Scenario: Poll 280 ကို MANUAL_SESSION ပြောင်းပြီး test လုပ်မယ်

#### ၁။ Mode ပြောင်းပါ (Admin)
```
WordPress → Edit Poll 280
Poll Mode: Auto Run → Manual Session
Update Item
```

#### ၂။ Session အသစ် စောင့်ပါ (3 မိနစ် cycle ဆိုရင်)
```
Current time: 13:00:00
Session s10 ends: 13:03:00
Session s11 starts: 13:03:00
```

#### ၃။ App မှာ vote လုပ်ပါ (User)
```
Flutter app → Poll 280
Select: Tiger
Amount: 2000 PNP
Submit Vote
```

#### ၄။ Log စစ်ပါ (Terminal)
```bash
# Expected logs:
Using session_id from backend: s11
Submitting poll vote: sessionId=s11
Poll vote submitted
```

#### ၅။ Admin Resolve လုပ်ပါ (2 မိနစ် နောက်)
```
WordPress → View Results → Poll 280
See: "Resolve Poll [Session: s11]"
Select: Tiger
Display: Instant
Click: "Set Winner & Award Points"
```

#### ၆။ Database စစ်ပါ (Verification)
```sql
-- Session resolutions စစ်ရန်:
SELECT 
    quiz_data->>'$.session_resolutions.s11.correct_index' as winner,
    quiz_data->>'$.session_resolutions.s11.display_timing' as timing
FROM 19kBefrnw_twork_engagement_items WHERE id = 280;
-- Expected: winner = 1, timing = 'instant'

-- Point transactions စစ်ရန်:
SELECT * FROM 19kBefrnw_twork_point_transactions 
WHERE order_id LIKE 'engagement:poll:280:session:s11:%';
-- Expected: User 2 က 2000×2=4000 PNP ရမယ်

-- Interactions စစ်ရန်:
SELECT * FROM 19kBefrnw_twork_user_interactions 
WHERE item_id = 280 AND session_id = 's11';
-- Expected: User 2 နဲ့ User 3 ရဲ့ votes မြင်ရမယ်
```

#### ၇။ Session အသစ် စမ်းပါ (1 မိနစ် နောက်)
```
Session s12 automatically starts!
Users can vote again! ✅
```

---

## 🎯 အကျဉ်းချုပ်

### ဘာတွေ ပြောင်းသွားလဲ:

| အချက် | AUTO_RUN | MANUAL_SESSION |
|-------|----------|----------------|
| Voting cycles | ✅ ရှိတယ် | ✅ ရှိတယ် (အတူတူပဲ) |
| Session IDs | ✅ s0, s1, s2 | ✅ s0, s1, s2 (အတူတူပဲ) |
| User re-voting | ✅ OK | ✅ OK (အတူတူပဲ) |
| Winner selection | 🤖 Random | 👤 **Admin ရွေးတယ်** ⭐ |
| Result timing | ⏰ Auto | ⚙️ **Admin ထိန်းချုပ်တယ်** ⭐ |

### ဘာတွေ အတူတူ ရှိနေတယ်:

✅ Users က session တိုင်း vote လုပ်လို့ရတယ်
✅ Timer countdown ရှိတယ် (2 min voting + 1 min result)
✅ Point deduction/rewards အလုပ်လုပ်တယ်
✅ Duplicate prevention ရှိတယ် (same session မှာ ထပ် vote မရဘူး)
✅ Session auto-reset (result ပြပြီး cycle အသစ် စတယ်)

### ဘာတွေ ပြောင်းသွားတယ်:

🔄 Winner selection: Random → **Admin manually picks**
🔄 Resolution trigger: Auto → **Admin decides when & how**
🔄 Result control: Fixed timing → **Instant OR Scheduled**

---

## ⚠️ အရေးကြီးတဲ့ မှတ်ချက်များ

### 1. Session Isolation (အရေးကြီးဆုံး!)

```
Session s0 resolved → Winner: Tiger
Session s1 resolved → Winner: Dragon
Session s2 NOT resolved → User တွေ "Waiting..." မြင်ရတယ်
```

**ဆိုလိုတာ:**
- Session တိုင်း သီးခြား resolve လုပ်ရမယ်
- s0 က Tiger win ပေမယ့် s1 က Dragon win ဖြစ်နိုင်တယ်
- Resolve မလုပ်ထားရင် user တွေ result မမြင်ရဘူး

### 2. Instant vs Scheduled

**Instant** ရွေးရင်:
```
Admin clicks → ချက်ချင်း result ပြတယ်
User app → ချက်ချင်း winner မြင်ရတယ်
Points → ချက်ချင်း ဝင်တယ်
```

**Scheduled** ရွေးရင်:
```
Admin clicks → Backend မှာ winner သိမ်းထားတယ်
User app → Timer ပြည့်မှ winner မြင်ရမယ် (original time)
Points → Admin click လုပ်တာနဲ့ ဝင်ပြီးသွားတယ် (ပေမယ့် app မှာ display မမြင်ရသေး)
```

### 3. Backend Files Upload လုပ်ရမယ်!

```
⚠️ CRITICAL: PHP code ၂ ခု upload မလုပ်ရင် အလုပ်မလုပ်ဘူး!

twork-rewards-system.php          (main plugin)
includes/class-poll-auto-run.php  (session handler)
```

Upload ပြီးမှ:
- Resolve UI မှာ "Manual Session" option ပေါ်လာမယ်
- Session-based resolution အလုပ်လုပ်မယ်

---

## 📱 Frontend Update လည်း လိုတယ်!

```dart
// engagement_carousel.dart updated:
if (pollMode == 'AUTO_RUN' || pollMode == 'MANUAL_SESSION') {
    // Calculate session_id for both modes
}
```

**Flutter app ကို restart လုပ်ပါ:**
```bash
# Hot restart (development)
Press 'r' in terminal

# OR full restart
Press 'R' in terminal
```

---

## 🧪 အလုပ်လုပ်မလုပ် Test လုပ်နည်း

### Quick Test (5 မိနစ်)

#### 1. Mode ပြောင်းပါ
```
WordPress → Edit Poll 280 → Mode: Manual Session → Update
```

#### 2. Vote လုပ်ပါ (App)
```
Poll 280 open → Select Tiger → 2000 PNP → Submit
```

#### 3. Log စစ်ပါ (Terminal)
```bash
# Expected:
✅ "Using session_id from backend: s12" (or similar)
✅ "Submitting poll vote: sessionId=s12"
✅ "Poll vote submitted"
```

#### 4. Wait 2 min (Voting closes)

#### 5. Resolve လုပ်ပါ (Admin)
```
WordPress → View Results → Poll 280
See: "Resolve Poll [Session: s12]"
Select: Tiger
Display: Instant
Submit
```

#### 6. App စစ်ပါ
```
App က winner ပြမယ်:
"🏆 Winner: TIGER! +4,000 PNP"
```

#### 7. Database စစ်ပါ (phpMyAdmin)
```sql
-- Transaction ဝင်မဝင် စစ်ရန်:
SELECT * FROM 19kBefrnw_twork_point_transactions 
WHERE order_id LIKE 'engagement:poll:280:session:s12:%'
ORDER BY created_at DESC;

-- Expected: 1 row (User 2, delta = +4000)
```

---

## 🔍 ပြဿနာ ဖြစ်ရင် စစ်ဆေးရန်

### ပြဿနာ ၁: "Already voted" error (session အသစ်မှာ)

**အကြောင်းရင်း:**
- Frontend က session_id မပို့လို့
- Backend က duplicate ထင်နေတာ

**စစ်ဆေးရန်:**
```bash
# Log စစ်ပါ:
grep "sessionId" /path/to/flutter/logs

# Expected:
✅ "Submitting poll vote: sessionId=s12"

# If missing (❌):
- Frontend code မ update ဖြစ်သေးဘူး
- App ကို restart လုပ်ပါ
```

**ဖြေရှင်းချက်:**
1. `engagement_carousel.dart` update ပြီးပြီလား စစ်ပါ
2. App ကို hot restart လုပ်ပါ (`r`)
3. ထပ် test လုပ်ပါ

---

### ပြဿနာ ၂: Resolve UI မပေါ်ဘူး

**အကြောင်းရင်း:**
- Poll mode က မှန်မှန် ပြောင်းမထားဘူး
- Voting period မပြီးသေးဘူး

**စစ်ဆေးရန်:**
```sql
-- Poll mode စစ်ပါ:
SELECT quiz_data->>'$.poll_mode' as mode 
FROM 19kBefrnw_twork_engagement_items 
WHERE id = 280;

-- Expected: 'manual_session' (NOT 'auto_run')
```

**ဖြေရှင်းချက်:**
1. WordPress → Edit Poll 280
2. Poll Mode → **Manual Session** ပြောင်းပါ
3. Update Item
4. Voting period ပြီးသွားဖို့ စောင့်ပါ (2 min)
5. Refresh → Resolve UI ပေါ်လာမယ်

---

### ပြဿနာ ၃: Winner point မဝင်ဘူး

**စစ်ဆေးရန်:**
```sql
-- Transaction table စစ်ပါ:
SELECT * FROM 19kBefrnw_twork_point_transactions 
WHERE order_id LIKE 'engagement:poll:280:session:%'
ORDER BY created_at DESC 
LIMIT 10;
```

**ဖြေရှင်းချက်:**
- Backend PHP files upload ပြီးပြီလား စစ်ပါ
- `award_poll_winner_points` function မှာ session_filter ပါလား စစ်ပါ
- Debug log ထဲမှာ error တွေ ရှိလား စစ်ပါ

---

## 📊 Database Queries (အသုံးဝင်တဲ့ queries)

### 1. Session ဘယ်နှစ်ခု resolved ပြီးပြီလဲ:
```sql
SELECT JSON_KEYS(quiz_data->'$.session_resolutions') as resolved_sessions
FROM 19kBefrnw_twork_engagement_items 
WHERE id = 280;
```

### 2. Session တစ်ခုရဲ့ votes:
```sql
SELECT 
    user_id,
    interaction_value,
    bet_amount,
    created_at
FROM 19kBefrnw_twork_user_interactions 
WHERE item_id = 280 AND session_id = 's12'
ORDER BY created_at;
```

### 3. Session တစ်ခုရဲ့ winners:
```sql
SELECT 
    user_id,
    delta as points_won,
    created_at
FROM 19kBefrnw_twork_point_transactions 
WHERE order_id LIKE 'engagement:poll:280:session:s12:%'
ORDER BY created_at;
```

### 4. မ resolve လုပ်ရသေးတဲ့ sessions:
```sql
-- All sessions with votes:
SELECT DISTINCT session_id 
FROM 19kBefrnw_twork_user_interactions 
WHERE item_id = 280 
ORDER BY session_id DESC;

-- Compare with resolved sessions in quiz_data->>'$.session_resolutions'
```

---

## ✅ Checklist

### Upload ပြီးပြီလား:

- [ ] `twork-rewards-system.php` uploaded
- [ ] `includes/class-poll-auto-run.php` uploaded
- [ ] `lib/widgets/engagement_carousel.dart` updated
- [ ] Flutter app restarted

### Poll settings မှန်လား:

- [ ] Poll Mode = "Manual Session"
- [ ] Poll Duration = 2 minutes (သို့မဟုတ် နှစ်သက်တဲ့ duration)
- [ ] Result Display = 1 minute (သို့မဟုတ် နှစ်သက်တဲ့ duration)
- [ ] Poll Status = Active

### Test လုပ်ပြီးပြီလား:

- [ ] Vote လုပ်လို့ ရတယ်
- [ ] Session ID log မှာ ပေါ်တယ် (e.g., "sessionId=s12")
- [ ] Voting ပိတ်ပြီး "Waiting..." မြင်ရတယ်
- [ ] Admin Resolve UI ပေါ်တယ်
- [ ] Winner ရွေးပြီး points ဝင်တယ်
- [ ] Session အသစ် စတဲ့အခါ ပြန် vote လုပ်လို့ ရတယ်

---

## 🎉 အောင်မြင်တဲ့ အချက်များ

✅ **User experience:** Session တိုင်း vote လုပ်လို့ ရတယ် (engagement မြင့်တယ်)
✅ **Admin control:** Winner ကို သေချာစွာ ရွေးနိုင်တယ် (fairness သေချာတယ်)
✅ **Flexible timing:** Result ကို instant (သို့) scheduled ပြလို့ ရတယ် (ပြင်ဆင်မှု ကောင်းတယ်)
✅ **Data integrity:** Session တိုင်း သီးခြား track လုပ်တယ် (audit trail ရှိတယ်)
✅ **Scalability:** Auto-reset ဖြစ်တာကြောင့် manual work နည်းတယ်

---

## 📞 ထပ်မံ အကူအညီ လိုရင်

**Backend logs:**
```bash
tail -f /path/to/wp-content/debug.log | grep "MANUAL_SESSION"
```

**Frontend logs:**
```bash
flutter logs | grep "session"
```

**Database inspection:**
```sql
-- Full poll config:
SELECT quiz_data FROM 19kBefrnw_twork_engagement_items WHERE id = 280;
```

---

**ရက်စွဲ**: 2026-03-23  
**Version**: 1.0  
**T-Work Rewards System**
