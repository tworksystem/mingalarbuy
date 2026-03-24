# Poll Points System - အပြည့်အစုံ ရှင်းလင်းချက် (Myanmar)

## အကျဉ်းချုပ်

✅ **စနစ်အခြေအနေ: မှန်ကန်စွာ အလုပ်လုပ်နေပါပြီ!**

Poll ကစားတဲ့အခါ point နှုတ်ယူခြင်း နှင့် winner ဖြစ်တဲ့အခါ point ပေါင်းထည့်ခြင်း **နှစ်ခုလုံး** တူညီတဲ့ database table ကို သုံးပါတယ်:

- **Primary Table**: `wp_twork_point_transactions`
- **လက်ကျန် တွက်ချက်ခြင်း**: `Balance = SUM(earn) - SUM(redeem)`
- **Cache**: `my_points`, `my_point`, `points_balance` (primary table ကနေ sync လုပ်ထားတာ)

---

## အဆင့်ဆင့် လုပ်ငန်းစဉ်

### ၁။ User က Poll ကစားတဲ့အခါ (Point နှုတ်ယူခြင်း)

```
[1] Frontend (Flutter App)
    ↓
    lib/widgets/engagement_carousel.dart
    _onPlayPressed() function က:
    • လက်ကျန် point ကို စစ်ဆေးမယ် (PointProvider.loadBalance)
    • လုံလောက်မှု စစ်မယ် (userBalance >= totalCost)
    • EngagementService.submitInteraction() ကို call လုပ်မယ်

[2] API Call
    ↓
    POST /wp-json/twork/v1/engagement/interact
    Body: {
      user_id: 456,
      item_id: 123,
      answer: "0,1",
      bet_amount_per_option: { "0": 2, "1": 3 }
    }

[3] Backend (WordPress)
    ↓
    wp-content/plugins/twork-rewards-system/twork-rewards-system.php
    rest_engagement_interact() function က:
    • လက်ကျန် စစ်ဆေးမယ် (get_user_points_balance)
    • လုံလောက်မှု စစ်မယ် (balance >= total_cost)
    • sync_user_points($user_id, -$total_cost, ...) ကို call လုပ်မယ်

[4] Database Insert (CRITICAL!)
    ↓
    Table: wp_twork_point_transactions
    INSERT:
    {
      user_id: 456,
      type: 'redeem',           ← နှုတ်ယူခြင်း (အနှုတ်)
      points: 2000,             ← ပမာဏ (အပေါင်းအဖြစ် သိမ်းတယ်)
      order_id: 'engagement:poll_cost:123:456:abc123',
      status: 'approved',
      created_at: '2026-03-23 10:00:00'
    }

[5] လက်ကျန် ပြန်တွက်မယ်
    ↓
    calculate_points_balance_from_transactions($user_id)
    
    SQL:
    Balance = SUM(
      CASE 
        WHEN type = 'earn' THEN +points    ← အရမ်းမှတ်သားပါ!
        WHEN type = 'redeem' THEN -points  ← အရမ်းမှတ်သားပါ!
      END
    )
    
    ဥပမာ: 10,000 - 2,000 = 8,000 PNP

[6] Meta Cache ကို update လုပ်မယ်
    ↓
    my_points = 8,000
    my_point = 8,000
    points_balance = 8,000

[7] Frontend က လက်ကျန်ကို refresh လုပ်မယ်
    ↓
    PointProvider.loadBalance() ကို call လုပ်ပြီး
    My PNP card မှာ 8,000 PNP ပြမယ် ✅
```

---

### ၂။ Winner ဖြစ်တဲ့အခါ (Point ပေါင်းထည့်ခြင်း)

```
[1] Admin က Poll ကို Resolve လုပ်မယ်
    ↓
    WordPress Admin → T-Work Rewards → Engagement
    "Random" (သို့) "Manual" button ကို နှိပ်မယ်
    
    သို့မဟုတ်
    
    AUTO_RUN Poll: Automatically resolve after voting period

[2] Backend က Winner ကို ရှာမယ်
    ↓
    award_poll_winner_points($item_id) function က:
    • Winning option ကို သတ်မှတ်မယ်
    • Winning option ကို ရွေးခဲ့တဲ့ users တွေကို ရှာမယ်
    • တစ်ယောက်ချင်းစီ reward ပေးမယ်

[3] Winner Point ပေါင်းထည့်မယ်
    ↓
    award_engagement_points_to_user($user_id, $reward_points, ...)
    
[4] Database Insert (SAME TABLE!)
    ↓
    Table: wp_twork_point_transactions  ← အရင်နဲ့ တူတဲ့ table!
    INSERT:
    {
      user_id: 456,
      type: 'earn',            ← အရမ်းမှတ်သားပါ! (အပေါင်း)
      points: 8000,
      order_id: 'engagement:poll:123:session:s1:456',
      status: 'approved',
      created_at: '2026-03-23 10:15:00'
    }

[5] လက်ကျန် ပြန်တွက်မယ် (တူတဲ့ calculation!)
    ↓
    calculate_points_balance_from_transactions($user_id)
    
    SQL: (အရင်နဲ့ တူတဲ့ query!)
    Balance = SUM(
      CASE 
        WHEN type = 'earn' THEN +points
        WHEN type = 'redeem' THEN -points
      END
    )
    
    ဥပမာ: (10,000 - 2,000) + 8,000 = 16,000 PNP ✅

[6] Meta Cache ကို update လုပ်မယ်
    ↓
    my_points = 16,000
    my_point = 16,000
    points_balance = 16,000

[7] Push Notification ပို့မယ်
    ↓
    FCM → User ရဲ့ phone
    Message: "You won: Soccer Match! 🏆"

[8] Frontend က winner notification ပြမယ်
    ↓
    lib/services/poll_winner_popup_service.dart
    • GET /wp-json/twork/v1/poll/results/{poll_id}/{session}?user_id={user_id}
    • Response: { user_won: true, points_earned: 8000, current_balance: 16000 }
    • PointProvider နှင့် AuthProvider ကို update လုပ်မယ်
    • In-app notification ပြမယ် (PointNotificationManager)
    • My PNP card မှာ 16,000 PNP ပြမယ် ✅
```

---

## အဓိက အချက်အလက်များ

### တူညီတဲ့ Database Table

**နှုတ်ယူတဲ့အခါ:**
```sql
INSERT INTO wp_twork_point_transactions (
  user_id, type, points, order_id, status
) VALUES (
  456,
  'redeem',  ← နှုတ်ယူခြင်း
  2000,
  'engagement:poll_cost:123:456:abc',
  'approved'
);
```

**Winner ဖြစ်တဲ့အခါ:**
```sql
INSERT INTO wp_twork_point_transactions (  ← တူတဲ့ table!
  user_id, type, points, order_id, status
) VALUES (
  456,
  'earn',    ← ရရှိခြင်း
  8000,
  'engagement:poll:123:session:s1:456',
  'approved'
);
```

### တူညီတဲ့ Balance Calculation

```sql
-- နှစ်ခုလုံးအတွက် တူတဲ့ calculation!
SELECT COALESCE(SUM(
  CASE 
    WHEN type = 'earn' AND status = 'approved' THEN points
    WHEN type = 'refund' AND status = 'approved' THEN points
    WHEN type = 'redeem' AND (status = 'approved' OR status = 'pending') THEN -points
    ELSE 0
  END
), 0) as balance
FROM wp_twork_point_transactions
WHERE user_id = 456;
```

**ရလဒ်:**
- Play မတိုင်မီ: 10,000 PNP
- Play လုပ်ပြီး (redeem): -2,000 PNP → 8,000 PNP
- Winner ဖြစ်ပြီး (earn): +8,000 PNP → 16,000 PNP

---

## စစ်ဆေးနည်းများ

### ၁။ User ရဲ့ poll transactions တွေကို ကြည့်မယ်

```sql
-- Poll play ခြင်းများ (နှုတ်ယူခြင်း)
SELECT 
  id,
  type,
  -points as amount,  -- အနှုတ်အဖြစ် ပြမယ်
  description,
  LEFT(order_id, 50) as order_id,
  created_at
FROM wp_twork_point_transactions
WHERE user_id = 456
AND order_id LIKE 'engagement:poll_cost:%'
ORDER BY created_at DESC
LIMIT 10;

-- Poll win ခြင်းများ (ဆုရခြင်း)
SELECT 
  id,
  type,
  points as amount,  -- အပေါင်းအဖြစ် ပြမယ်
  description,
  LEFT(order_id, 50) as order_id,
  created_at
FROM wp_twork_point_transactions
WHERE user_id = 456
AND order_id LIKE 'engagement:poll:%'
AND order_id NOT LIKE 'engagement:poll_cost:%'
ORDER BY created_at DESC
LIMIT 10;
```

### ၂။ လက်ကျန် မှန်ကန်မှု စစ်ဆေးမယ်

```sql
-- Ledger (primary) နဲ့ Meta cache (cached) တူညီမှု စစ်မယ်
SELECT 
  user_id,
  COALESCE(SUM(
    CASE 
      WHEN type = 'earn' AND status = 'approved' THEN points
      WHEN type = 'redeem' AND status IN ('approved','pending') THEN -points
      ELSE 0
    END
  ), 0) as ledger_balance,
  (SELECT meta_value FROM wp_usermeta 
   WHERE user_id = 456 AND meta_key = 'points_balance') as meta_balance
FROM wp_twork_point_transactions
WHERE user_id = 456
GROUP BY user_id;
```

**မျှော်လင့်ထားတဲ့ ရလဒ်:**
- `ledger_balance` = `meta_balance` ဖြစ်ရမယ်
- မတူရင် meta ကို refresh လုပ်ဖို့ လိုအပ်တယ်

### ၃။ App ကနေ စစ်ဆေးမယ်

**Flutter Debug Console မှာ run မယ်:**
```dart
import 'package:ecommerce_int2/services/point_verification_service.dart';

// Verify balance and print detailed report
await PointVerificationService.printVerificationReport('456');
```

**Output ဥပမာ:**
```
╔═══════════════════════════════════════════════════════════════╗
║       POLL POINTS SYSTEM - BALANCE VERIFICATION REPORT       ║
╚═══════════════════════════════════════════════════════════════╝

User ID: 456
Timestamp: 2026-03-23T10:30:00+00:00

┌─────────────────────────────────────────────────────────────┐
│ BALANCE STATUS                                              │
├─────────────────────────────────────────────────────────────┤
│ Ledger Balance (PRIMARY):      16000 PNP                    │
│ Meta Cache Balance:             16000 PNP                    │
│ Consistency Status:        ✅ CONSISTENT                     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ POLL TRANSACTIONS                                           │
├─────────────────────────────────────────────────────────────┤
│ Poll Plays (Deductions):      5 plays │       10000 PNP     │
│ Poll Wins (Rewards):          3 wins  │       24000 PNP     │
│ Net Poll Impact:                       │       14000 PNP     │
└─────────────────────────────────────────────────────────────┘

✅ Balance is consistent between ledger and meta cache.
```

---

## အရေးကြီးတဲ့ အချက်များ

### ✅ တူတဲ့ Table ကို အသုံးပြုခြင်း

**နှုတ်ယူခြင်း (Deduction):**
- Table: `wp_twork_point_transactions`
- Type: `redeem`
- Order ID: `engagement:poll_cost:{poll}:{user}:{time}`

**ဆုပေးခြင်း (Winner Reward):**
- Table: `wp_twork_point_transactions` ← **တူတဲ့ table!**
- Type: `earn`
- Order ID: `engagement:poll:{poll}:session:{session}:{user}`

### ✅ တူတဲ့ Balance Calculation

နှစ်ခုလုံးက **တူတဲ့ function** ကို သုံးတယ်:
```php
calculate_points_balance_from_transactions($user_id)
```

နှစ်ခုလုံးက **တူတဲ့ SQL query** ကို run တယ်:
```sql
Balance = SUM(earn) - SUM(redeem)
```

### ✅ Duplicate Prevention (ထပ်တူ မဖြစ်အောင် ကာကွယ်ခြင်း)

**Order ID Uniqueness:**
- Database မှာ `order_id` column က UNIQUE constraint ရှိတယ်
- တူတဲ့ `order_id` နဲ့ နှစ်ကြိမ် insert လုပ်လို့ မရဘူး
- Code က insert မလုပ်ခင် existing row ကို စစ်ဆေးတယ်

**AUTO_RUN Polls:**
- MySQL advisory locks (`GET_LOCK`) သုံးတယ်
- Multiple requests တစ်ချိန်တည်း ဝင်လာရင် ထပ်တူ မဖြစ်အောင် ကာကွယ်တယ်

---

## ဥပမာ - လက်တွေ့ကစားကြည့်မယ်

### အခြေအနေ

**User A:**
- အစမှာ: 10,000 PNP
- Poll: "Soccer Match - Who will win?"
- Options: Man United (0), Liverpool (1), Arsenal (2)
- Cost per option: 1,000 PNP per unit
- Reward multiplier: 4x

### အဆင့် ၁ - User A ကစားတယ်

**Action:**
- Man United ကို ရွေးတယ် (Option 0)
- Amount = 2 units
- Total cost = 1,000 × 2 = 2,000 PNP

**Database မှာ ဖြစ်တဲ့အရာ:**
```sql
-- wp_twork_point_transactions table ထဲကို row အသစ် insert လုပ်မယ်
INSERT INTO wp_twork_point_transactions 
VALUES (
  ...,
  456,           -- user_id
  'redeem',      -- type (နှုတ်ယူခြင်း)
  2000,          -- points
  'Poll entry cost: Soccer Match (-2000 points)',  -- description
  'engagement:poll_cost:123:456:abc123',           -- order_id
  'approved',    -- status
  '2026-03-23 10:00:00'  -- created_at
);

-- လက်ကျန်ကို ပြန်တွက်မယ်
SELECT SUM(
  CASE 
    WHEN type = 'earn' THEN points
    WHEN type = 'redeem' THEN -points
  END
) FROM wp_twork_point_transactions WHERE user_id = 456;

-- Result: 10,000 - 2,000 = 8,000 PNP ✅
```

**App မှာ မြင်ရမယ့်အရာ:**
- My PNP card: 8,000 PNP ပြမယ် ✅
- Success message: "ကစားမှု အောင်မြင်ပါသည်။ 2000 points နှုတ်ယူပြီးပါပြီ။"
- Point History: "Poll entry cost: Soccer Match (-2,000 points)"

### အဆင့် ၂ - Admin က Resolve လုပ်တယ်

**Action:**
- Admin က "Random" button ကို နှိပ်တယ်
- System က Man United (Option 0) ကို winner အဖြစ် ရွေးတယ်
- User A က Man United ကို ရွေးခဲ့တဲ့အတွက် winner ဖြစ်တယ်!

**Backend မှာ ဖြစ်တဲ့အရာ:**
```php
// Winner reward တွက်မယ်
$user_bet_pnp = 1000 × 2 = 2,000 PNP  // User A က 2 units bet လုပ်ခဲ့တယ်
$reward = $user_bet_pnp × 4 = 8,000 PNP  // Multiplier 4x

// award_engagement_points_to_user() ကို call လုပ်မယ်
```

**Database မှာ ဖြစ်တဲ့အရာ:**
```sql
-- wp_twork_point_transactions table ထဲကို row အသစ် insert လုပ်မယ် (SAME TABLE!)
INSERT INTO wp_twork_point_transactions 
VALUES (
  ...,
  456,           -- user_id (User A)
  'earn',        -- type (ရရှိခြင်း) ← အရမ်းမှတ်သားပါ!
  8000,          -- points (reward)
  'Poll winner reward: Soccer Match (+8000 points)',  -- description
  'engagement:poll:123:session::456',  -- order_id
  'approved',    -- status
  '2026-03-23 10:15:00'  -- created_at
);

-- လက်ကျန်ကို ပြန်တွက်မယ် (SAME CALCULATION!)
SELECT SUM(
  CASE 
    WHEN type = 'earn' THEN points     -- 8000 ကို ပေါင်းမယ်
    WHEN type = 'redeem' THEN -points  -- 2000 ကို နှုတ်မယ်
  END
) FROM wp_twork_point_transactions WHERE user_id = 456;

-- Result: (10,000 - 2,000) + 8,000 = 16,000 PNP ✅
```

**App မှာ မြင်ရမယ့်အရာ:**
- Push notification: "You won: Soccer Match! 🏆"
- In-app notification ပေါ်မယ် (popup)
- My PNP card: 16,000 PNP ပြမယ် ✅
- Point History:
  - "Poll entry cost: Soccer Match (-2,000 points)"
  - "Poll winner reward: Soccer Match (+8,000 points)" ← အသစ်

---

## နည်းပညာ အသေးစိတ်

### Database Schema

```sql
CREATE TABLE wp_twork_point_transactions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,              -- User ID
  type VARCHAR(20) NOT NULL,            -- 'earn', 'redeem', 'refund'
  points INT UNSIGNED NOT NULL,         -- ပမာဏ (အပေါင်းသာ)
  description TEXT,                     -- ဖော်ပြချက်
  order_id VARCHAR(191) UNIQUE,         -- Unique key (ထပ်တူ မဖြစ်အောင်)
  status VARCHAR(20) DEFAULT 'approved', -- 'approved', 'pending', 'rejected'
  expires_at DATETIME NULL,             -- သက်တမ်း (optional)
  created_at DATETIME NOT NULL,         -- ဖန်တီးသည့် အချိန်
  
  INDEX idx_user_id (user_id),
  INDEX idx_order_id (order_id),
  INDEX idx_type_status (type, status)
);
```

### Transaction Types ရှင်းလင်းချက်

| Type | Status | Effect | အသုံးပြုရာ |
|------|--------|--------|---------|
| `earn` | `approved` | **+points** | Poll winner, Quiz reward, Order cashback |
| `redeem` | `approved` | **-points** | Admin က approve လုပ်ပြီးသော exchange |
| `redeem` | `pending` | **-points** | User က request လုပ်ထားသော exchange (မ approve သေးဘူး) |
| `refund` | `approved` | **+points** | Reject လုပ်ပြီး ပြန်အမ်းပေးခြင်း |

### ဘာကြောင့် `points` column မှာ အပေါင်းသာ သိမ်းလဲ?

**အဖြေ:** `type` column က positive/negative ကို ဆုံးဖြတ်တယ်:
- `type = 'earn'` → **အပေါင်း** (+points)
- `type = 'redeem'` → **အနှုတ်** (-points)

**ဥပမာ:**
```sql
Row 1: type='earn',   points=8000  → Balance effect: +8000
Row 2: type='redeem', points=2000  → Balance effect: -2000
```

**Balance calculation:**
```sql
Balance = (8000) + (-2000) = 6000
```

ဒါက professional database design pattern တစ်ခု ဖြစ်ပါတယ်။ Separate column (`type`) က transaction ရဲ့ nature ကို သတ်မှတ်ပြီး `points` က magnitude (အရွယ်အစား) ကိုသာ သိမ်းတယ်။

---

## Testing

### Manual Test Steps

**၁။ User ရဲ့ လက်ကျန်ကို မှတ်သားပါ:**
```
SELECT * FROM wp_twork_point_transactions 
WHERE user_id = 456 
ORDER BY created_at DESC LIMIT 5;
```

**၂။ Poll ကို ကစားပါ:**
- App ကို ဖွင့်မယ်
- Poll တစ်ခုကို ရွေးမယ်
- Option တစ်ခု (သို့) တစ်ခုထက်ပို ရွေးမယ်
- Amount သတ်မှတ်မယ်
- "ကစားမည်" button ကို နှိပ်မယ်

**၃။ Deduction စစ်ဆေးပါ:**
```sql
-- အသစ်ဆုံး deduction ကို ကြည့်မယ်
SELECT * FROM wp_twork_point_transactions 
WHERE user_id = 456 
AND type = 'redeem'
AND order_id LIKE 'engagement:poll_cost:%'
ORDER BY created_at DESC LIMIT 1;

-- မျှော်လင့်ထားတာ:
-- type = 'redeem'
-- points = (သင် select လုပ်ခဲ့တဲ့ cost)
-- order_id စတယ် 'engagement:poll_cost:' နဲ့
```

**၄။ App မှာ လက်ကျန် စစ်မယ်:**
- My PNP card က လျော့သွားရမယ် ✅
- Point History မှာ "Poll entry cost: ..." ပေါ်ရမယ်

**၅။ Admin က Poll ကို Resolve လုပ်ပါ:**
- WordPress Admin → T-Work Rewards → Engagement
- Poll ကို ရှာမယ်
- "Random" သို့မဟုတ် "Manual" နဲ့ winner သတ်မှတ်မယ်

**၆။ Winner Reward စစ်ဆေးပါ:**
```sql
-- Winner reward ကို ကြည့်မယ်
SELECT * FROM wp_twork_point_transactions 
WHERE user_id = 456 
AND type = 'earn'
AND order_id LIKE 'engagement:poll:%'
AND order_id NOT LIKE 'engagement:poll_cost:%'
ORDER BY created_at DESC LIMIT 1;

-- မျှော်လင့်ထားတာ (User A က winner ဖြစ်ရင်):
-- type = 'earn'  ← အရမ်းမှတ်သားပါ!
-- points = (bet amount × multiplier)
-- order_id စတယ် 'engagement:poll:' နဲ့
```

**၇။ App မှာ winner notification စစ်မယ်:**
- Push notification လာရမယ်: "You won: Soccer Match! 🏆"
- In-app popup ပေါ်ရမယ်
- My PNP card က တက်သွားရမယ် ✅
- Point History မှာ "Poll winner reward: ..." ပေါ်ရမယ်

**၈။ နောက်ဆုံး verification:**
```sql
-- နှစ်ခု လုံး ရှိမရှိ စစ်မယ် (SAME TABLE မှာ)
SELECT 
  id,
  type,
  CASE WHEN type = 'earn' THEN points ELSE -points END as delta,
  description,
  created_at
FROM wp_twork_point_transactions
WHERE user_id = 456
AND order_id LIKE 'engagement:poll%'
ORDER BY created_at ASC;

-- မျှော်လင့်ထားတဲ့ result:
-- Row 1: type='redeem', delta=-2000 (deduction)
-- Row 2: type='earn',   delta=+8000 (winner reward)
-- နှစ်ခုလုံး wp_twork_point_transactions table မှာ ရှိရမယ်!
```

---

## Error Logs မှာ ကြည့်ရမယ့် အရာများ

### ✅ အောင်မြင်သော Deduction

```
T-Work Rewards: [POLL DEDUCTION] Transaction created. ID: 1234, User: 456, Type: redeem, Points: -2000
T-Work Rewards: Poll play point deduction — User: 456, Item: 123, Cost: 2000, Balance: 10000 → 8000 (expected: 8000, match: YES)
T-Work Rewards: Poll deduction ledger row verified. Row ID: 1234, Table: wp_twork_point_transactions
```

### ✅ အောင်မြင်သော Winner Reward

```
T-Work Rewards: [POLL WINNER REWARD] Transaction created. ID: 1235, User: 456, Type: earn, Points: +8000
T-Work Rewards: award_engagement_points_to_user COMPLETE. User: 456, Points: +8000, Balance: 8000 → 16000 (delta: 8000), Type: poll
T-Work Rewards: Poll winner reward SUCCESS — User: 456, Poll: 123, Session: s1, Reward: 8000, Balance: 8000 → 16000
```

### ✅ Duplicate Prevention (မျှော်လင့်ထားသော behavior)

```
T-Work Rewards: Duplicate order_id detected (expected) — skipping insert. User: 456, Order: engagement:poll:123:session:s1:456, Existing ID: 1235
T-Work Rewards: Poll winner reward already distributed — skipping. Poll: 123, Session: s1, User: 456
```

### ❌ Error များ (ဖြစ်သင့်မဖြစ်သင့် များ)

```
T-Work Rewards: CRITICAL - Poll deduction failed! User: 456, Item: 123, Cost: 2000
T-Work Rewards: CRITICAL - Poll winner reward failed! User: 456, Poll: 123, Reward: 8000
T-Work Rewards: BALANCE INCONSISTENCY DETECTED! User: 456, Ledger: 16000, Meta: 15000, Difference: 1000
```

ဒီ messages တွေ မြင်ရရင် system administrator ကို ချက်ချင်း အကြောင်းကြားပါ!

---

## သင်ယူရမည့် အဓိက အချက်များ

### 🎯 Key Point #1: တူညီတဲ့ Table

```
Deduction →  wp_twork_point_transactions (type='redeem')
                          ↓
                     SAME TABLE!
                          ↓
Reward    →  wp_twork_point_transactions (type='earn')
```

### 🎯 Key Point #2: တူညီတဲ့ Calculation

```
Deduction validation:  Balance = SUM(earn) - SUM(redeem)
                                      ↓
                               SAME FORMULA!
                                      ↓
Winner reward amount:  Balance = SUM(earn) - SUM(redeem)
```

### 🎯 Key Point #3: အဆင့်ဆင့် မှန်ကန်မှု

```
[Play]  insert redeem row → calculate balance → update meta → app syncs
                                    ↓
                         SAME balance calculation
                                    ↓
[Win]   insert earn row   → calculate balance → update meta → app syncs
```

---

## နိဂုံး

✅ **စနစ် အခြေအနေ: ပရော်ဖက်ရှင်နယ် အဆင့်**

**သင့် စနစ်က မှန်ကန်စွာ အလုပ်လုပ်နေပါပြီ!**

Point နှုတ်ယူခြင်း နှင့် winner ဆုပေးခြင်း **နှစ်ခုလုံးက**:
- ✅ **တူညီတဲ့ table ကို အသုံးပြုတယ်**: `wp_twork_point_transactions`
- ✅ **တူညီတဲ့ calculation ကို အသုံးပြုတယ်**: `Balance = SUM(earn) - SUM(redeem)`
- ✅ **တူညီတဲ့ meta sync ကို အသုံးပြုတယ်**: `refresh_user_point_meta_from_ledger()`

**ဘာကြောင့် ဒါက အရေးကြီးလဲ?**

ဒီ design ကြောင့်:
1. **Balance က အမြဲတမ်း မှန်ကန်တယ်** - Single source of truth (wp_twork_point_transactions)
2. **Audit trail ကောင်းတယ်** - ဘယ် point က ဘယ်ကလာတယ်ဆိုတာ အကုန် သိနိုင်တယ်
3. **Duplicate မဖြစ်ဘူး** - Unique order_id constraint + code-level checks
4. **Performance ကောင်းတယ်** - Single SUM query ဖြင့် balance ကို မြန်မြန် တွက်နိုင်တယ်
5. **Scalable ဖြစ်တယ်** - User ဘယ်လောက်များများ သုံးနိုင်တယ်

**Winner points က နှုတ်ယူခဲ့တဲ့ နေရာတည်းကို ပြန်ထည့်ပေးတယ်!** 🎉

ဒါကြောင့် သင့် စနစ်မှာ ဘာမှ ပြင်ဖို့ မလိုဘူး - **အကုန် မှန်ကန်စွာ အလုပ်လုပ်နေပါပြီ!** ✅

---

## နောက်ထပ် အရင်းအမြစ်များ

- **Technical Analysis**: `docs/POLL_POINTS_FLOW_ANALYSIS.md`
- **Testing Guide**: `docs/POLL_POINTS_TESTING_GUIDE.md`
- **Verification Service**: `lib/services/point_verification_service.dart`
- **API Endpoint**: `/wp-json/twork/v1/points/verify-balance/{user_id}`

သင့်မှာ မေးခွန်းရှိရင် သို့မဟုတ် ထပ်စစ်ဆေးချင်တာရှိရင် အသိပေးပါ! 🙏
