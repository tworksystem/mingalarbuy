# 🎯 MANUAL_SESSION Poll Mode - Complete Guide

## 📋 Overview

**Problem**: AUTO_RUN polls create too many winners (random selection each session)

**Solution**: MANUAL_SESSION mode - Admin manually picks winner for each session

## 🔄 Poll Mode Comparison

| Feature | AUTO_RUN | MANUAL_SESSION | MANUAL |
|---------|----------|----------------|--------|
| **Multi-session voting** | ✅ Yes (s0, s1, s2...) | ✅ Yes (s0, s1, s2...) | ❌ No (one vote only) |
| **Winner selection** | 🤖 Random (highest votes) | 👤 Admin picks manually | 👤 Admin picks manually |
| **Result timing** | ⏰ Auto (cycle-based) | ⚙️ Instant OR Scheduled | ⚡ Instant only |
| **Session cycling** | ✅ Auto-reset per cycle | ✅ Auto-reset per cycle | ❌ No cycles |
| **Best for** | Hands-free operation | Admin-controlled fairness | One-time polls |

---

## 🔧 How to Convert AUTO_RUN → MANUAL_SESSION

### Step 1: Edit Poll in WordPress Admin

1. Go to **T-Work Rewards → Engagement Items**
2. Click **Edit** on your AUTO_RUN poll
3. Scroll to **Poll Mode** dropdown
4. Change from `Auto Run` to `Manual Session`
5. **Keep** the existing timer settings:
   - Poll Duration: e.g., 2 minutes
   - Result Display Duration: e.g., 1 minute
6. Click **Update Item**

### Step 2: What Happens Automatically

```
BEFORE (AUTO_RUN):
┌─────────────────────┐
│ Session 0: 2 min    │ → Vote closes → Random winner → Points awarded → Reset
│ Session 1: 2 min    │ → Vote closes → Random winner → Points awarded → Reset
│ Session 2: 2 min    │ → Vote closes → Random winner → Points awarded → Reset
└─────────────────────┘

AFTER (MANUAL_SESSION):
┌─────────────────────┐
│ Session 0: 2 min    │ → Vote closes → ⏸️ WAIT → Admin picks winner → Points awarded → Reset
│ Session 1: 2 min    │ → Vote closes → ⏸️ WAIT → Admin picks winner → Points awarded → Reset
│ Session 2: 2 min    │ → Vote closes → ⏸️ WAIT → Admin picks winner → Points awarded → Reset
└─────────────────────┘
```

### Step 3: Existing Data Preserved

✅ **All existing votes are kept** (no data loss)
✅ **Session IDs remain intact** (s0, s1, s2...)
✅ **Timer schedules continue** (poll_voting_end_time unchanged)
✅ **Unresolved sessions remain unresolved** (admin can resolve later)

---

## 👨‍💼 Admin Workflow: Resolving MANUAL_SESSION Polls

### When to Resolve

**Option A: Resolve Instantly** (as soon as voting period ends)
- Go to admin immediately when session closes
- Pick winner
- Result shows to users instantly

**Option B: Resolve on Schedule** (at natural session end time)
- Go to admin anytime before next session starts
- Pick winner
- Result shows at the scheduled session end time

### Resolve UI

1. Go to **T-Work Rewards → Engagement Items**
2. Click **View Results** on your poll
3. You'll see a blue resolve card:

```
┌─────────────────────────────────────────────────────┐
│ 🏆 Resolve Poll – Set Correct Answer    [Session: s5] │
├─────────────────────────────────────────────────────┤
│ 📌 Manual Session Mode: This poll runs in 2-minute    │
│    cycles. You are resolving Session s5. Winners     │
│    from this session will receive points.            │
├─────────────────────────────────────────────────────┤
│ Voting has ended. Choose winning answer:             │
│                                                       │
│ [Random – Pick from voted options]                   │
│   Randomly selects from options that got votes       │
│                                                       │
│ ────────────────────────────────────────────────     │
│                                                       │
│ Manual – Select winning option:                      │
│ [Dropdown: Tiger / Dragon / ...]                     │
│                                                       │
│ Result Display:                                       │
│ ○ Instant – Show result immediately                  │
│ ○ Scheduled – Show at session end time               │
│                                                       │
│ [Set Winner & Award Points]                          │
└─────────────────────────────────────────────────────┘
```

### Step-by-Step Resolution

#### Example: Session s5 just closed (voting ended)

**INSTANT DISPLAY:**
1. Select winning option: "Tiger"
2. Choose **Instant** radio button
3. Click **Set Winner & Award Points**
4. Result: 
   - ✅ Session s5 marked as resolved
   - ✅ Winners get points immediately
   - ✅ FCM notifications sent
   - ✅ App shows result immediately (voting_end_time changed to NOW)
   - ⏰ 1 minute later: Session s6 starts automatically

**SCHEDULED DISPLAY:**
1. Select winning option: "Dragon"
2. Choose **Scheduled** radio button
3. Click **Set Winner & Award Points**
4. Result:
   - ✅ Session s5 marked as resolved
   - ✅ Winners get points immediately (backend)
   - ⏰ App shows result at original scheduled time (2-min mark)
   - ⏰ 1 minute later: Session s6 starts automatically

---

## 🔄 Session Lifecycle (MANUAL_SESSION)

```
CYCLE DURATION: poll_duration + result_display_duration
Example: 2 min voting + 1 min result = 3 min total

┌────────────────────────────────────────────────────────────────┐
│                     Session s0 (0-3 min)                        │
├────────────────────────────────────────────────────────────────┤
│ 00:00-02:00 │ VOTING ACTIVE    │ Users vote Tiger/Dragon      │
│ 02:00       │ VOTING CLOSES    │ ⏸️ Wait for admin            │
│ 02:00-03:00 │ Admin picks winner│ Resolve UI available         │
│ 03:00       │ RESULT SHOWS     │ Display winner & reset       │
├────────────────────────────────────────────────────────────────┤
│                     Session s1 (3-6 min)                        │
├────────────────────────────────────────────────────────────────┤
│ 03:00-05:00 │ VOTING ACTIVE    │ Users vote again             │
│ 05:00       │ VOTING CLOSES    │ ⏸️ Wait for admin            │
│ 05:00-06:00 │ Admin picks winner│ Resolve UI available         │
│ 06:00       │ RESULT SHOWS     │ Display winner & reset       │
└────────────────────────────────────────────────────────────────┘
```

### Key Differences from AUTO_RUN:

| Timing | AUTO_RUN | MANUAL_SESSION |
|--------|----------|----------------|
| **Vote collection** | 2 min | 2 min (same) |
| **Winner selection** | Auto (at 2 min mark) | Admin picks (anytime before 3 min) |
| **Result display** | Auto (2-3 min period) | Admin-controlled (instant OR 2-3 min) |
| **Next session** | Auto-starts at 3 min | Auto-starts at 3 min (same) |

---

## 🗄️ Database Schema

### Session Resolutions Storage

```php
// Stored in quiz_data JSON:
{
  "poll_mode": "manual_session",
  "poll_actual_start_at": "2026-03-23 12:54:32",
  "poll_duration": 2,
  "result_display_duration": 1,
  
  // Per-session resolutions (new!)
  "session_resolutions": {
    "s0": {
      "correct_index": 1,
      "mode": "manual",
      "resolved_at": "2026-03-23 12:56:15",
      "resolved_by": 1,
      "display_timing": "instant"
    },
    "s1": {
      "correct_index": 0,
      "mode": "random",
      "resolved_at": "2026-03-23 12:59:45",
      "resolved_by": 1,
      "display_timing": "scheduled"
    }
  },
  
  // Current session winner (for feed display)
  "correct_index": 0,
  "poll_correct_answer_mode": "random",
  "current_resolved_session": "s1"
}
```

### Interaction Records

```sql
-- Each session stores votes with session_id
SELECT * FROM wp_twork_user_interactions 
WHERE item_id = 280 
ORDER BY created_at DESC;

| user_id | item_id | interaction_value | session_id | bet_amount | created_at          |
|---------|---------|-------------------|------------|------------|---------------------|
| 2       | 280     | 1                 | s2         | 3          | 2026-03-23 13:02:10 |
| 3       | 280     | 0                 | s2         | 2          | 2026-03-23 13:01:45 |
| 2       | 280     | 0                 | s1         | 2          | 2026-03-23 12:59:30 |
| 3       | 280     | 1                 | s1         | 4          | 2026-03-23 12:58:50 |
| 2       | 280     | 1                 | s0         | 1          | 2026-03-23 12:55:20 |
```

**Key Points:**
- ✅ Same user can vote in multiple sessions
- ✅ Each session tracked by session_id (s0, s1, s2...)
- ✅ Duplicate prevention: One vote per user per session

---

## 🎮 User Experience (Frontend)

### What Users See

#### During Voting (Session s5 Active):
```
┌─────────────────────────────────────┐
│ 🔥 4X Win Poll                      │
│                                     │
│ 🐯 Tiger    vs    🐉 Dragon         │
│                                     │
│ Select: [☑️ Tiger] [ Dragon]        │
│ Amount: [2000 PNP]                  │
│                                     │
│ ⏱️ 01:34 remaining                  │
│                                     │
│ [Submit Vote] (2000 PNP)            │
└─────────────────────────────────────┘
```

#### After Voting (Waiting for Resolution):
```
┌─────────────────────────────────────┐
│ 🔥 4X Win Poll                      │
│                                     │
│ ✅ Thanks for voting!                │
│ Your choice: Tiger (2000 PNP)       │
│                                     │
│ ⏳ Waiting for results...           │
│ (Admin will announce winner)        │
│                                     │
│ ⏱️ Results soon                     │
└─────────────────────────────────────┘
```

#### When Result Shows (Admin Resolved):
```
┌─────────────────────────────────────┐
│ 🔥 4X Win Poll                      │
│                                     │
│ 🏆 Winner: TIGER! 🐯                │
│                                     │
│ You won: +8,000 PNP 🎉              │
│ New balance: 45,000 PNP             │
│                                     │
│ Votes: Tiger 67% | Dragon 33%       │
│                                     │
│ ⏱️ Next vote: 00:42                 │
└─────────────────────────────────────┘
```

---

## 🧪 Testing Workflow

### Test Scenario: Convert Poll 280 from AUTO_RUN → MANUAL_SESSION

#### 1. Preparation
```sql
-- Check current mode
SELECT id, title, quiz_data->>'$.poll_mode' as poll_mode 
FROM 19kBefrnw_twork_engagement_items 
WHERE id = 280;

-- Expected: poll_mode = 'auto_run'
```

#### 2. Convert to MANUAL_SESSION
1. WordPress Admin → Edit Poll 280
2. Change Poll Mode → **Manual Session**
3. Keep timers: Poll Duration = 2, Result = 1
4. Click **Update Item**

#### 3. Verify Conversion
```sql
-- Check updated mode
SELECT quiz_data->>'$.poll_mode' as poll_mode,
       quiz_data->>'$.poll_actual_start_at' as started_at,
       quiz_data->>'$.poll_duration' as duration
FROM 19kBefrnw_twork_engagement_items 
WHERE id = 280;

-- Expected: poll_mode = 'manual_session'
-- started_at and duration should be UNCHANGED
```

#### 4. Test Multi-Session Voting

**Session s10 (Current):**
```
1. User 2 votes on Tiger (2000 PNP)
2. User 3 votes on Dragon (3000 PNP)
3. Wait 2 minutes (voting closes)
4. Check frontend: Shows "Waiting for results..."
```

**Admin Resolution:**
```
1. Go to WordPress Admin → View Results (Poll 280)
2. See: "Resolve Poll – Set Correct Answer [Session: s10]"
3. Select "Tiger" from dropdown
4. Choose "Instant" display
5. Click "Set Winner & Award Points"
```

**Expected Results:**
```sql
-- Check session resolution
SELECT quiz_data->>'$.session_resolutions.s10.correct_index' as winner,
       quiz_data->>'$.session_resolutions.s10.mode' as mode,
       quiz_data->>'$.session_resolutions.s10.display_timing' as timing
FROM 19kBefrnw_twork_engagement_items 
WHERE id = 280;

-- Expected: winner = 1 (Tiger), mode = 'manual', timing = 'instant'

-- Check point transactions
SELECT * FROM 19kBefrnw_twork_point_transactions 
WHERE order_id LIKE 'engagement:poll:280:session:s10:%'
ORDER BY created_at DESC;

-- Expected: 2 records (User 2 gets 2000×2=4000 PNP, User 3 gets nothing)
```

**Session s11 (Next):**
```
1. Wait 1 minute (result display period)
2. Session s11 starts automatically
3. Users can vote AGAIN (multi-session!)
4. Admin resolves s11 separately
```

---

## 💡 Best Practices

### When to Use Each Mode

**AUTO_RUN** - Best for:
- 24/7 engagement without admin involvement
- High-volume polls where fairness = randomness
- When you trust vote distribution (highest votes win)

**MANUAL_SESSION** - Best for:
- High-stakes polls where admin verifies fairness
- Need to investigate suspicious voting patterns per session
- Want consistent winner control across sessions
- Scheduled events with admin-announced winners

**MANUAL** - Best for:
- One-time surveys or feedback polls
- Special event polls (no repeats)
- A/B testing where users vote once only

### Instant vs Scheduled Display

**Instant Display** - Use when:
- Admin is actively monitoring
- Want immediate gratification for voters
- Breaking news / live events
- Low suspense tolerance

**Scheduled Display** - Use when:
- Want dramatic reveal at specific time
- Batch multiple decisions
- Give admin time to review before showing
- Maintain consistent cycle timing

### Session Management Tips

1. **Track Session Numbers**
   - Resolve UI shows: `[Session: s5]`
   - Database: Check `session_resolutions` object
   - Frontend logs: Search for `session_id=s5`

2. **Handle Missed Sessions**
   - If admin misses resolving s5, users see "Waiting for results..."
   - Admin can resolve s5 later (even if s6 has started)
   - Points awarded when resolved (retroactive)

3. **Monitor Voting Patterns**
   ```sql
   -- Check votes per session
   SELECT session_id, 
          COUNT(*) as total_votes,
          SUM(bet_amount) as total_pnp_wagered
   FROM 19kBefrnw_twork_user_interactions 
   WHERE item_id = 280 
   GROUP BY session_id 
   ORDER BY session_id DESC;
   ```

4. **Verify Point Awards**
   ```sql
   -- Check which sessions have awarded points
   SELECT SUBSTRING_INDEX(SUBSTRING_INDEX(order_id, ':session:', -1), ':', 1) as session,
          COUNT(*) as winners,
          SUM(delta) as total_points_awarded
   FROM 19kBefrnw_twork_point_transactions 
   WHERE order_id LIKE 'engagement:poll:280:session:%'
   GROUP BY session
   ORDER BY session DESC;
   ```

---

## 🐛 Troubleshooting

### Issue 1: "Already voted" error in new session

**Symptoms:**
- User voted in s0
- Session s1 started
- User tries to vote again → "already_voted" error

**Diagnosis:**
```
Check frontend logs:
- Look for: "Using session_id from backend: s1"
- If missing: Frontend not sending session_id
```

**Fix:**
- Ensure frontend code updated (engagement_carousel.dart)
- Hot restart Flutter app
- Check backend response includes `current_session_id`

### Issue 2: Resolve UI not showing

**Symptoms:**
- Voting closed but no "Resolve Poll" card

**Diagnosis:**
```
Check poll_mode:
SELECT quiz_data->>'$.poll_mode' as mode 
FROM 19kBefrnw_twork_engagement_items 
WHERE id = 280;

Expected: 'manual_session' or 'manual'
NOT: 'auto_run'
```

**Fix:**
- Edit poll in admin
- Change mode to MANUAL_SESSION
- Save

### Issue 3: Winners from multiple sessions get points

**Symptoms:**
- Resolved s5 only
- But users from s4 also got points

**Diagnosis:**
```php
// Check award_poll_winner_points session filter
// Should filter: WHERE item_id = 280 AND session_id = 's5'
```

**Fix:**
- Verify backend code passes session_filter
- Check SQL query includes session_id in WHERE clause

### Issue 4: Frontend shows "Pending resolution" forever

**Symptoms:**
- Admin resolved the session
- Frontend still shows "Waiting for results..."

**Diagnosis:**
```
1. Check session_resolutions in database:
   SELECT quiz_data->>'$.session_resolutions' 
   FROM wp_twork_engagement_items WHERE id = 280;

2. Check frontend poll_result response:
   - Look for: resolution_pending: false
   - Look for: winning_index: 1
```

**Fix:**
- Refresh engagement feed (pull to refresh)
- Check if voting_end_time updated for instant display
- Verify backend REST API returns correct data

---

## 📊 Monitoring & Analytics

### Admin Dashboard Queries

```sql
-- 1. Check all sessions and their resolution status
SELECT 
    JSON_KEYS(quiz_data->'$.session_resolutions') as resolved_sessions,
    quiz_data->>'$.poll_mode' as mode,
    quiz_data->>'$.poll_actual_start_at' as started_at
FROM 19kBefrnw_twork_engagement_items 
WHERE id = 280;

-- 2. Count votes per session
SELECT 
    session_id,
    COUNT(DISTINCT user_id) as unique_voters,
    COUNT(*) as total_votes,
    SUM(bet_amount) as total_pnp_bet
FROM 19kBefrnw_twork_user_interactions 
WHERE item_id = 280 
GROUP BY session_id 
ORDER BY session_id DESC 
LIMIT 10;

-- 3. Check winner payouts per session
SELECT 
    SUBSTRING_INDEX(SUBSTRING_INDEX(order_id, ':session:', -1), ':', 1) as session,
    COUNT(*) as winners,
    SUM(delta) as total_pnp_awarded,
    MIN(created_at) as first_payout,
    MAX(created_at) as last_payout
FROM 19kBefrnw_twork_point_transactions 
WHERE order_id LIKE 'engagement:poll:280:session:%'
GROUP BY session 
ORDER BY session DESC 
LIMIT 10;

-- 4. Find unresolved sessions (votes collected, no winner set)
SELECT DISTINCT session_id 
FROM 19kBefrnw_twork_user_interactions 
WHERE item_id = 280 
  AND session_id NOT IN (
    -- Extract resolved session keys from JSON
    SELECT JSON_KEYS(quiz_data->'$.session_resolutions')
    FROM 19kBefrnw_twork_engagement_items 
    WHERE id = 280
  );
```

### Log Monitoring

```bash
# Backend resolution logs
grep "MANUAL_SESSION Poll.*resolved" /path/to/debug.log | tail -20

# Frontend session logs
flutter logs | grep "session_id"

# Point award logs
grep "Poll winner reward.*engagement:poll:280" /path/to/debug.log
```

---

## ⚙️ Advanced Configuration

### Instant Reveal with Custom Timing

Want to reveal instantly but delay result display by 30 seconds?

**Solution**: Use scheduled display + manually update voting_end_time:

```php
// In resolve handler, add 30-second delay:
if ($result_timing === 'instant_delayed') {
    $now_ts = strtotime(current_time('mysql'));
    $reveal_ts = $now_ts + 30; // 30 second delay
    $quiz_data['poll_voting_end_time'] = date('Y-m-d H:i:s', $reveal_ts);
}
```

### Automatic Fallback Resolution

Don't want unresolved sessions to block indefinitely?

**Solution**: Add cron job to auto-resolve abandoned sessions:

```php
// Pseudo-code:
foreach (manual_session_polls as $poll) {
    $current_session = calculate_current_session($poll);
    $previous_session = 's' . (intval(substr($current_session, 1)) - 1);
    
    if (!is_session_resolved($poll, $previous_session)) {
        // Auto-resolve with random after 1 hour delay
        if (session_ended_over_1_hour_ago($poll, $previous_session)) {
            resolve_poll_random($poll->id, $previous_session);
        }
    }
}
```

---

## 📝 Migration Checklist

### Before Converting AUTO_RUN → MANUAL_SESSION

- [ ] Document current session number
- [ ] Export voting data (backup)
- [ ] Notify users of change (optional)
- [ ] Test on staging environment first

### During Conversion

- [ ] Change poll_mode in admin UI
- [ ] Verify timer settings unchanged
- [ ] Upload backend PHP files to server
- [ ] Hot restart Flutter app (or publish update)

### After Conversion

- [ ] Test voting in new session
- [ ] Verify session_id appears in logs
- [ ] Resolve one session manually (test)
- [ ] Confirm point awards correct
- [ ] Monitor for 3-5 session cycles

### Rollback Plan (if needed)

```sql
-- Emergency rollback to AUTO_RUN
UPDATE 19kBefrnw_twork_engagement_items 
SET quiz_data = JSON_SET(
    quiz_data,
    '$.poll_mode', 'auto_run'
)
WHERE id = 280;
```

---

## 🚀 Deployment

### Files to Upload

```
wp-content/plugins/twork-rewards-system/
├── twork-rewards-system.php (updated)
└── includes/
    └── class-poll-auto-run.php (updated)

lib/widgets/
└── engagement_carousel.dart (updated)
```

### Deployment Steps

1. **Backend:**
   ```bash
   # Upload via FTP/SSH
   scp twork-rewards-system.php user@server:/path/to/wp-content/plugins/twork-rewards-system/
   scp class-poll-auto-run.php user@server:/path/to/wp-content/plugins/twork-rewards-system/includes/
   ```

2. **Frontend:**
   ```bash
   # Hot restart (development)
   flutter run  # Press 'r' in terminal
   
   # Production build
   flutter build apk --release
   # Upload to Play Store / distribute
   ```

3. **Verify:**
   - Check WordPress admin: New "Manual Session" option visible
   - Check Flutter app: session_id logs present
   - Test end-to-end: Vote → Resolve → Points awarded

---

## 📞 Support

### Common Questions

**Q: Can I mix AUTO_RUN and MANUAL_SESSION sessions?**
A: No. When you change mode, all future sessions use the new mode. Past sessions keep their resolutions.

**Q: What happens to unresolved AUTO_RUN sessions after switching?**
A: They remain randomly resolved. MANUAL_SESSION only affects NEW sessions after the switch.

**Q: Can users vote in old sessions after switching?**
A: No. Users can only vote in the CURRENT active session. Past sessions are closed.

**Q: How to stop ALL sessions temporarily?**
A: Change poll status to "Inactive" or "Draft" in admin.

---

## 🎓 Summary

### Key Improvements

✅ **Session-based voting preserved** (users vote multiple times)
✅ **Admin winner control** (no more random winners)
✅ **Flexible result timing** (instant OR scheduled)
✅ **Per-session resolution tracking** (audit trail)
✅ **Seamless user experience** (same UI, better control)

### Migration Path

```
AUTO_RUN (Random winners)
    ↓
    Edit poll → Change mode
    ↓
MANUAL_SESSION (Admin-controlled winners)
    ↓
    Each session: Admin picks winner
    ↓
    Happy users + Fair results! 🎉
```

---

**Created**: 2026-03-23
**Version**: 1.0
**Author**: T-Work Rewards Development Team
