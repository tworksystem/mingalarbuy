# 🎨 AUTO_RUN vs MANUAL_SESSION - Visual Comparison

## 🔄 Mode Comparison Chart

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         POLL MODE FEATURES                              │
├──────────────────┬─────────────────┬─────────────────┬─────────────────┤
│ Feature          │ AUTO_RUN        │ MANUAL_SESSION  │ MANUAL          │
├──────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Multi-session    │ ✅ Yes          │ ✅ Yes          │ ❌ No           │
│ voting           │ (s0,s1,s2...)   │ (s0,s1,s2...)   │ (one vote only) │
├──────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Winner           │ 🤖 Random       │ 👤 Admin picks  │ 👤 Admin picks  │
│ selection        │ (highest votes) │ (manual)        │ (manual)        │
├──────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Result timing    │ ⏰ Auto         │ ⚙️ Flexible     │ ⚡ Instant      │
│                  │ (cycle-based)   │ (instant/sched) │ (on resolve)    │
├──────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Admin workload   │ 🟢 None         │ 🟡 Per session  │ 🔵 Once         │
├──────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Best for         │ 24/7 automation │ Controlled fair │ One-time survey │
└──────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

---

## 🔄 AUTO_RUN Poll Flow

```
┌────────────────────────────────────────────────────────────────────┐
│                        AUTO_RUN POLL CYCLE                         │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Session s0 (0-3 min):                                            │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ 00:00  Poll starts (ACTIVE)                              │    │
│  │        └─> User 2 votes Tiger (2000 PNP)                 │    │
│  │        └─> User 3 votes Dragon (3000 PNP)                │    │
│  │                                                           │    │
│  │ 02:00  Voting closes                                     │    │
│  │        └─> 🤖 AUTO: Pick highest votes (Dragon 60%)      │    │
│  │        └─> ✅ Award points to Dragon voters              │    │
│  │        └─> 📱 Show result in app                         │    │
│  │                                                           │    │
│  │ 03:00  Result ends                                       │    │
│  │        └─> 🔄 AUTO: Reset & start s1                     │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                    │
│  Session s1 (3-6 min):                                            │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ 03:00  Poll opens AGAIN (users can re-vote)             │    │
│  │        └─> User 2 votes Dragon (4000 PNP)                │    │
│  │        └─> User 3 votes Tiger (2000 PNP)                 │    │
│  │                                                           │    │
│  │ 05:00  Voting closes                                     │    │
│  │        └─> 🤖 AUTO: Pick highest votes (Tiger 55%)       │    │
│  │        └─> ✅ Award points to Tiger voters               │    │
│  │                                                           │    │
│  │ 06:00  Result ends → 🔄 Reset → s2 starts...            │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ♾️  Cycles continue infinitely...                                │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘

🎯 USER EXPERIENCE:
   ✅ Vote every cycle (high engagement)
   ⚠️ Winner is random (may feel unfair if patterns exist)
   ✅ No admin work needed (automated)
   ⚠️ Too many winners over time
```

---

## 👨‍💼 MANUAL_SESSION Poll Flow

```
┌────────────────────────────────────────────────────────────────────┐
│                    MANUAL_SESSION POLL CYCLE                       │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Session s0 (0-3 min):                                            │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ 00:00  Poll starts (ACTIVE)                              │    │
│  │        └─> User 2 votes Tiger (2000 PNP)                 │    │
│  │        └─> User 3 votes Dragon (3000 PNP)                │    │
│  │                                                           │    │
│  │ 02:00  Voting closes                                     │    │
│  │        └─> ⏸️  WAIT: Admin needs to resolve              │    │
│  │        └─> 📱 App shows "Waiting for results..."         │    │
│  │                                                           │    │
│  │ 02:30  👤 ADMIN ACTION:                                  │    │
│  │        └─> WordPress: View Results → Resolve Poll UI     │    │
│  │        └─> Select: Tiger (admin choice)                  │    │
│  │        └─> Display: Instant                              │    │
│  │        └─> Click: "Set Winner & Award Points"            │    │
│  │        └─> ✅ Award points to Tiger voters               │    │
│  │        └─> 📱 App instantly shows result                 │    │
│  │                                                           │    │
│  │ 03:00  Result ends                                       │    │
│  │        └─> 🔄 AUTO: Reset & start s1                     │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                    │
│  Session s1 (3-6 min):                                            │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ 03:00  Poll opens AGAIN (users can re-vote)             │    │
│  │        └─> User 2 votes Dragon (4000 PNP)                │    │
│  │        └─> User 3 votes Tiger (2000 PNP)                 │    │
│  │        └─> User 5 votes Dragon (5000 PNP)                │    │
│  │                                                           │    │
│  │ 05:00  Voting closes                                     │    │
│  │        └─> ⏸️  WAIT: Admin needs to resolve              │    │
│  │                                                           │    │
│  │ 05:15  👤 ADMIN ACTION:                                  │    │
│  │        └─> Select: Dragon (admin verified fair)          │    │
│  │        └─> Display: Scheduled                            │    │
│  │        └─> ✅ Points awarded (backend)                   │    │
│  │        └─> ⏰ App will show result at 05:00 (original)   │    │
│  │                                                           │    │
│  │ 06:00  Result ends → 🔄 Reset → s2 starts...            │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ♾️  Cycles continue with admin resolving each session...         │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘

🎯 USER EXPERIENCE:
   ✅ Vote every cycle (high engagement)
   ✅ Fair winner (admin verified)
   ✅ Flexible result timing
   ⚠️ Requires admin presence each cycle
```

---

## 🎮 User Journey Comparison

### Scenario: 4X Win Poll (Tiger vs Dragon)

#### AUTO_RUN Mode:
```
┌─────────────────────────────────────────────────────────────┐
│ 12:00 PM │ User 2 opens app                                │
│          │ 🔥 4X Win Poll [02:00 remaining]                │
│          │ Select: Tiger → 2000 PNP → Submit               │
│          │ ✅ "Vote submitted!"                            │
├─────────────────────────────────────────────────────────────┤
│ 12:02 PM │ Voting closes                                   │
│          │ 🤖 System picks winner: Dragon (random)         │
│          │ 📱 App shows: "🏆 Winner: DRAGON"               │
│          │ 😢 User 2 lost (voted Tiger)                    │
├─────────────────────────────────────────────────────────────┤
│ 12:03 PM │ New session starts                              │
│          │ 🔥 4X Win Poll [02:00 remaining]                │
│          │ Select: Dragon → 3000 PNP → Submit              │
│          │ ✅ "Vote submitted!"                            │
├─────────────────────────────────────────────────────────────┤
│ 12:05 PM │ Voting closes                                   │
│          │ 🤖 System picks: Tiger (random)                 │
│          │ 😢 User 2 lost again (voted Dragon)             │
└─────────────────────────────────────────────────────────────┘

USER FEELING: 😤 "Unlucky! Random feels unfair!"
```

#### MANUAL_SESSION Mode:
```
┌─────────────────────────────────────────────────────────────┐
│ 12:00 PM │ User 2 opens app                                │
│          │ 🔥 4X Win Poll [02:00 remaining]                │
│          │ Select: Tiger → 2000 PNP → Submit               │
│          │ ✅ "Vote submitted!"                            │
├─────────────────────────────────────────────────────────────┤
│ 12:02 PM │ Voting closes                                   │
│          │ ⏳ App shows: "Waiting for results..."          │
│          │ (Admin is checking votes...)                    │
├─────────────────────────────────────────────────────────────┤
│ 12:02:30 │ 👤 Admin sees:                                  │
│          │    Tiger: 40% (Users: 2, 4, 7)                  │
│          │    Dragon: 60% (Users: 3, 5, 6)                 │
│          │ Admin picks: Tiger (strategic choice)           │
│          │ Display: Instant                                │
│          │ Click: "Set Winner & Award Points"              │
├─────────────────────────────────────────────────────────────┤
│ 12:02:31 │ 📱 App shows: "🏆 Winner: TIGER!"               │
│          │ 🎉 User 2 won: +8,000 PNP                       │
│          │ 😊 "Admin chose my answer! Fair!"               │
├─────────────────────────────────────────────────────────────┤
│ 12:03 PM │ New session starts                              │
│          │ 🔥 4X Win Poll [02:00 remaining]                │
│          │ Select: Dragon → 3000 PNP → Submit              │
│          │ ✅ Can vote again!                              │
└─────────────────────────────────────────────────────────────┘

USER FEELING: 😊 "Admin picks winner! Feels fair and controlled!"
```

---

## 📊 Session Timeline Visualization

### AUTO_RUN Timeline:
```
00:00                   02:00                03:00                05:00
  │─────── VOTING ───────│─── RESULT ───│─────── VOTING ───────│─── RESULT ───│
  │                      │               │                      │               │
  │ Users vote           │ 🤖 Auto pick  │ Users re-vote        │ 🤖 Auto pick  │
  │ (Session s0)         │ Show winner   │ (Session s1)         │ Show winner   │
  │                      │ Award points  │                      │ Award points  │
  └──────────────────────┴───────────────┴──────────────────────┴───────────────┘
  
  ⚡ No admin work needed
  ⚠️ Winner is random (highest votes + hash)
```

### MANUAL_SESSION Timeline:
```
00:00                   02:00                03:00                05:00
  │─────── VOTING ───────│─── RESULT ───│─────── VOTING ───────│─── RESULT ───│
  │                      │               │                      │               │
  │ Users vote           │ ⏸️ Wait for    │ Users re-vote        │ ⏸️ Wait for    │
  │ (Session s0)         │    admin      │ (Session s1)         │    admin      │
  │                      │ 👤 Admin pick  │                      │ 👤 Admin pick  │
  │                      │ Show winner   │                      │ Show winner   │
  │                      │ Award points  │                      │ Award points  │
  └──────────────────────┴───────────────┴──────────────────────┴───────────────┘
  
  👨‍💼 Admin resolves each session
  ✅ Winner is controlled (admin verified)
```

### MANUAL Timeline (Non-session):
```
00:00                               [Admin decides]
  │───────────── VOTING ─────────────│────── RESULT ──────> [END]
  │                                  │
  │ Users vote (one time only)       │ 👤 Admin resolves
  │                                  │ Show winner
  │                                  │ Award points
  │                                  │ 🛑 Poll ends (no reset)
  └──────────────────────────────────┴────────────────────────────>
  
  👨‍💼 Admin resolves once
  ❌ No multi-voting
```

---

## 🎯 Winner Selection Logic

### AUTO_RUN:
```php
// Automatic winner calculation
foreach ($vote_counts as $idx => $count) {
    if ($count > $max_votes) {
        $max_votes = $count;
        $candidates = [$idx];
    } elseif ($count === $max_votes) {
        $candidates[] = $idx; // Tie
    }
}

// Deterministic random (uses hash, not wp_rand)
$hash = md5($poll_id . '_' . $session_id);
$winning_index = $candidates[$hash % count($candidates)];

// Example:
// Tiger: 45 votes
// Dragon: 60 votes ← Winner! 🐉
// Automatic, no admin input
```

### MANUAL_SESSION:
```php
// Admin manually selects winner
$winning_index = $_POST['manual_correct_index']; // Admin's choice

// Store per session
$quiz_data['session_resolutions']['s0'] = [
    'correct_index' => 0, // Tiger (admin chose)
    'mode' => 'manual',
    'resolved_at' => '2026-03-23 12:02:30'
];

// Example:
// Tiger: 45 votes ← Admin picks! 🐯
// Dragon: 60 votes (higher, but admin chose Tiger)
// Reason: Admin verified Tiger voters were legitimate
```

---

## 💰 Point Award Comparison

### AUTO_RUN - Session s0:
```sql
-- All Dragon voters get points (highest votes)
INSERT INTO wp_twork_point_transactions 
(user_id, delta, order_id)
VALUES
(3, 12000, 'engagement:poll:280:session:s0:3'),  -- Dragon voter
(5, 20000, 'engagement:poll:280:session:s0:5'),  -- Dragon voter
(6,  8000, 'engagement:poll:280:session:s0:6');  -- Dragon voter

-- User 2 (Tiger voter) gets nothing ❌
-- User 4 (Tiger voter) gets nothing ❌
```

### MANUAL_SESSION - Session s0:
```sql
-- Admin picked Tiger (even though Dragon had more votes)
-- Only Tiger voters get points
INSERT INTO wp_twork_point_transactions 
(user_id, delta, order_id)
VALUES
(2,  8000, 'engagement:poll:280:session:s0:2'),  -- Tiger voter ✅
(4, 16000, 'engagement:poll:280:session:s0:4'),  -- Tiger voter ✅
(7, 12000, 'engagement:poll:280:session:s0:7');  -- Tiger voter ✅

-- User 3 (Dragon voter) gets nothing (despite higher votes)
-- Admin verified Tiger voters were fair play
```

---

## 🔄 Session State Transitions

### AUTO_RUN:
```
┌──────────────┐
│   ACTIVE     │ ← Users voting (0-2 min)
│ (session s0) │
└──────┬───────┘
       │ 02:00 - Vote closes
       ▼
┌──────────────┐
│   AUTO       │ ← System calculates winner
│  RESOLVE     │   (highest votes, deterministic hash)
│ (2 seconds)  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  SHOWING     │ ← Display result (2-3 min)
│   RESULTS    │   Points already awarded
└──────┬───────┘
       │ 03:00 - Result period ends
       ▼
┌──────────────┐
│   RESET      │ ← Clear votes, clear winner
│ (instant)    │   Increment session: s0 → s1
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   ACTIVE     │ ← New voting opens
│ (session s1) │   Users can vote again
└──────────────┘
       │
      ...continues
```

### MANUAL_SESSION:
```
┌──────────────┐
│   ACTIVE     │ ← Users voting (0-2 min)
│ (session s0) │
└──────┬───────┘
       │ 02:00 - Vote closes
       ▼
┌──────────────┐
│   PENDING    │ ← Waiting for admin
│  RESOLUTION  │   App shows: "Waiting for results..."
│  (0-60 min)  │   Admin can take their time
└──────┬───────┘
       │ Admin clicks "Resolve"
       ▼
┌──────────────┐
│   INSTANT    │ ← Option A: Show result NOW
│   DISPLAY    │   voting_end_time = NOW
│             │   User sees winner immediately
└──────┬───────┘
       │ OR
┌──────────────┐
│  SCHEDULED   │ ← Option B: Show at original time
│   DISPLAY    │   voting_end_time = unchanged (02:00)
│             │   User sees winner at scheduled time
└──────┬───────┘
       │ 03:00 - Result period ends
       ▼
┌──────────────┐
│   RESET      │ ← Clear votes, clear winner
│ (instant)    │   Increment session: s0 → s1
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   ACTIVE     │ ← New voting opens
│ (session s1) │   Admin resolves s1 separately
└──────────────┘
       │
      ...continues
```

---

## 🗄️ Database State Comparison

### AUTO_RUN - After 3 sessions:

**Engagement Item:**
```json
{
  "poll_mode": "auto_run",
  "poll_actual_start_at": "2026-03-23 12:00:00",
  "poll_duration": 2,
  "result_display_duration": 1,
  "correct_index": -1,  // ← NOT stored (calculated per session)
  "current_resolved_session": ""  // ← Not tracked
}
```

**User Interactions:**
```sql
| user_id | item_id | interaction_value | session_id | bet_amount | created_at          |
|---------|---------|-------------------|------------|------------|---------------------|
| 2       | 280     | 0                 | s2         | 4          | 2026-03-23 12:06:10 |
| 3       | 280     | 1                 | s2         | 3          | 2026-03-23 12:06:05 |
| 2       | 280     | 1                 | s1         | 3          | 2026-03-23 12:03:20 |
| 3       | 280     | 0                 | s1         | 2          | 2026-03-23 12:03:15 |
| 2       | 280     | 0                 | s0         | 2          | 2026-03-23 12:00:30 |
| 3       | 280     | 1                 | s0         | 3          | 2026-03-23 12:00:25 |
```

**Point Transactions:**
```sql
| user_id | delta  | order_id                              | created_at          |
|---------|--------|---------------------------------------|---------------------|
| 2       | +16000 | engagement:poll:280:session:s2:2      | 2026-03-23 12:08:01 |
| 2       | +12000 | engagement:poll:280:session:s1:2      | 2026-03-23 12:05:01 |
| 3       | +12000 | engagement:poll:280:session:s0:3      | 2026-03-23 12:02:01 |
```

### MANUAL_SESSION - After 3 sessions:

**Engagement Item:**
```json
{
  "poll_mode": "manual_session",
  "poll_actual_start_at": "2026-03-23 12:00:00",
  "poll_duration": 2,
  "result_display_duration": 1,
  "correct_index": 0,  // ← Current session winner (Tiger)
  "current_resolved_session": "s2",
  "session_resolutions": {  // ← Per-session tracking!
    "s0": {
      "correct_index": 0,
      "mode": "manual",
      "resolved_at": "2026-03-23 12:02:15",
      "resolved_by": 1,
      "display_timing": "instant"
    },
    "s1": {
      "correct_index": 1,
      "mode": "manual",
      "resolved_at": "2026-03-23 12:05:30",
      "resolved_by": 1,
      "display_timing": "scheduled"
    },
    "s2": {
      "correct_index": 0,
      "mode": "manual",
      "resolved_at": "2026-03-23 12:08:10",
      "resolved_by": 1,
      "display_timing": "instant"
    }
  }
}
```

**User Interactions:**
```sql
-- Same as AUTO_RUN (users vote the same way)
| user_id | item_id | interaction_value | session_id | bet_amount | created_at          |
|---------|---------|-------------------|------------|------------|---------------------|
| 2       | 280     | 0                 | s2         | 4          | 2026-03-23 12:06:10 |
| 3       | 280     | 1                 | s2         | 3          | 2026-03-23 12:06:05 |
| 2       | 280     | 1                 | s1         | 3          | 2026-03-23 12:03:20 |
| 3       | 280     | 0                 | s1         | 2          | 2026-03-23 12:03:15 |
| 2       | 280     | 0                 | s0         | 2          | 2026-03-23 12:00:30 |
| 3       | 280     | 1                 | s0         | 3          | 2026-03-23 12:00:25 |
```

**Point Transactions:**
```sql
-- Session winners determined by ADMIN, not votes!
| user_id | delta  | order_id                              | created_at          |
|---------|--------|---------------------------------------|---------------------|
| 2       | +16000 | engagement:poll:280:session:s2:2      | 2026-03-23 12:08:10 |
| 3       | +12000 | engagement:poll:280:session:s1:3      | 2026-03-23 12:05:30 |
| 2       | +8000  | engagement:poll:280:session:s0:2      | 2026-03-23 12:02:15 |
```

**Key Difference:**
- s0: Admin picked Tiger (index 0) → User 2 won
- s1: Admin picked Dragon (index 1) → User 3 won  
- s2: Admin picked Tiger (index 0) → User 2 won
- Winners align with admin choices, NOT vote counts!

---

## 🎭 Use Cases

### When to Use AUTO_RUN:
```
✅ 24/7 operation (no admin monitoring)
✅ Trust vote distribution (highest votes = fair)
✅ High engagement (users vote frequently)
✅ Low stakes (points are just for fun)

Example: Daily trivia polls, fun predictions
```

### When to Use MANUAL_SESSION:
```
✅ High stakes (valuable prizes)
✅ Fraud detection needed (admin verifies patterns)
✅ Strategic control (admin can balance outcomes)
✅ Event-based (announce winners dramatically)

Example: Tournament brackets, contest finals, VIP polls
```

### When to Use MANUAL (non-session):
```
✅ One-time survey (no repeats)
✅ Feedback collection (vote once, analyze later)
✅ A/B testing (need stable dataset)
✅ Official voting (elections, decisions)

Example: Feature requests, satisfaction surveys
```

---

## 🧪 Testing Matrix

### Test Scenario: 4X Win Poll Conversion

| Step | AUTO_RUN | MANUAL_SESSION | Expected Result |
|------|----------|----------------|-----------------|
| 1. Create poll | ✅ Mode: auto_run | | Poll cycles automatically |
| 2. User 2 votes s0 | ✅ Tiger (2000) | | Vote recorded |
| 3. User 3 votes s0 | ✅ Dragon (3000) | | Vote recorded |
| 4. s0 closes (2 min) | 🤖 Auto-resolve | | Winner: Dragon (higher) |
| 5. Check points | ✅ User 3 gets points | | User 2 gets nothing |
| 6. **Convert to MANUAL_SESSION** | | ✅ Change mode | No data lost |
| 7. User 2 votes s1 | | ✅ Tiger (2000) | Vote recorded |
| 8. User 3 votes s1 | | ✅ Dragon (4000) | Vote recorded |
| 9. s1 closes | | ⏸️ Waits | App: "Waiting..." |
| 10. **Admin resolves s1** | | 👤 Pick Tiger | Despite Dragon higher |
| 11. Check points | | ✅ User 2 gets points | User 3 gets nothing |
| 12. s2 starts | | ✅ Auto-opens | Users can vote again |

**Validation:**
```sql
-- Verify session s0 (AUTO_RUN, random):
SELECT * FROM wp_twork_point_transactions 
WHERE order_id LIKE '%:session:s0:%';
-- Expected: Dragon voters got points

-- Verify session s1 (MANUAL_SESSION, admin chose):
SELECT * FROM wp_twork_point_transactions 
WHERE order_id LIKE '%:session:s1:%';
-- Expected: Tiger voters got points (admin's choice)

-- Verify mode change preserved data:
SELECT COUNT(*) FROM wp_twork_user_interactions WHERE item_id = 280;
-- Expected: 6+ rows (votes from both s0 and s1 intact)
```

---

## 📈 Analytics & Monitoring

### Admin Dashboard Query:

```sql
-- Session-by-session breakdown
SELECT 
    s.session,
    s.votes,
    s.total_pnp_bet,
    COALESCE(p.winners, 0) as winners,
    COALESCE(p.total_awarded, 0) as total_awarded,
    r.admin_choice,
    r.vote_winner,
    CASE 
        WHEN r.admin_choice IS NULL THEN '⏸️ Pending'
        WHEN r.admin_choice = r.vote_winner THEN '✅ Matched'
        ELSE '🔀 Override'
    END as resolution_type
FROM
    -- Vote counts per session
    (SELECT session_id as session, 
            COUNT(*) as votes, 
            SUM(bet_amount) as total_pnp_bet
     FROM wp_twork_user_interactions 
     WHERE item_id = 280 
     GROUP BY session_id) s
LEFT JOIN
    -- Point awards per session
    (SELECT SUBSTRING_INDEX(SUBSTRING_INDEX(order_id, ':session:', -1), ':', 1) as session,
            COUNT(*) as winners,
            SUM(delta) as total_awarded
     FROM wp_twork_point_transactions 
     WHERE order_id LIKE 'engagement:poll:280:session:%'
     GROUP BY session) p
ON s.session = p.session
LEFT JOIN
    -- Resolution metadata
    (SELECT JSON_UNQUOTE(JSON_EXTRACT(quiz_data, 
            CONCAT('$.session_resolutions.', s.session, '.correct_index'))) as admin_choice,
            (SELECT interaction_value 
             FROM wp_twork_user_interactions 
             WHERE item_id = 280 AND session_id = s.session 
             GROUP BY interaction_value 
             ORDER BY COUNT(*) DESC LIMIT 1) as vote_winner
     FROM wp_twork_engagement_items 
     WHERE id = 280) r
ORDER BY s.session DESC;
```

**Sample Output:**
```
| session | votes | pnp_bet | winners | awarded | admin_choice | vote_winner | resolution |
|---------|-------|---------|---------|---------|--------------|-------------|------------|
| s2      | 15    | 45000   | 8       | 128000  | 0 (Tiger)    | 1 (Dragon)  | 🔀 Override |
| s1      | 20    | 60000   | 12      | 192000  | 1 (Dragon)   | 1 (Dragon)  | ✅ Matched  |
| s0      | 18    | 54000   | 0       | 0       | NULL         | 0 (Tiger)   | ⏸️ Pending  |
```

**Insights:**
- s2: Admin overrode vote winner (strategic choice)
- s1: Admin matched vote winner (fair outcome)
- s0: Not resolved yet (users waiting)

---

## 🎓 Best Practices

### 1. Mode Selection Strategy

```
START
  │
  ├─> Need 24/7 automation? ──YES──> AUTO_RUN
  │                            NO
  │                            │
  ├─> Users vote multiple times? ──NO──> MANUAL (one-time)
  │                                YES
  │                                │
  └─> Need admin control? ──YES──> MANUAL_SESSION
                            NO
                            │
                        AUTO_RUN (with monitoring)
```

### 2. Conversion Timing

**Best time to convert AUTO_RUN → MANUAL_SESSION:**
- ✅ Between sessions (during result display period)
- ✅ When admin is available to resolve
- ⚠️ Not mid-voting (let session complete first)

**Safe conversion:**
```
12:00-12:02 │ Voting (s5) → Let finish
12:02-12:03 │ Result → 👍 CONVERT NOW
12:03-12:05 │ Voting (s6) → Admin resolves
```

### 3. Resolution Schedule

**High-engagement polls (2-min cycles):**
```
Strategy: Admin reserves 8-hour shifts
- 9:00 AM - 5:00 PM: Admin monitors & resolves
- 5:00 PM - 9:00 AM: Switch to AUTO_RUN (overnight)
```

**Low-frequency polls (15-min cycles):**
```
Strategy: Admin checks every hour
- Resolve all pending sessions in batch
- Use scheduled display to maintain timing
```

---

## 🎉 Success Metrics

### After MANUAL_SESSION deployment:

**Fairness:**
```
✅ Suspicious voting patterns detected & filtered
✅ Winner selection documented (audit trail)
✅ User complaints reduced (fair outcomes)
```

**Engagement:**
```
✅ Multi-session voting preserved
✅ User retention improved (can participate repeatedly)
✅ Higher bet amounts (users trust fairness)
```

**Control:**
```
✅ Admin can adjust outcomes strategically
✅ Instant OR scheduled flexibility
✅ Per-session winner tracking
```

**Efficiency:**
```
✅ Auto-reset reduces manual work
✅ Session isolation simplifies resolution
✅ Clear audit trail for compliance
```

---

**Created:** 2026-03-23  
**Version:** 1.0  
**Status:** ✅ Ready for Production
