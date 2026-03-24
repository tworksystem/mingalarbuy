# ⚡ MANUAL_SESSION အမြန်လမ်းညွှန် (Burmese)

## 🎯 အချက်အလက် (1 မိနစ်ဖတ်ရန်)

### ပြဿနာ:
```
AUTO_RUN Poll → Winner အများကြီး (random ဖြစ်နေလို့) ❌
```

### ဖြေရှင်းချက်:
```
MANUAL_SESSION Mode → Admin က winner ရွေးတယ် ✅
                    → User တွေ အကြိမ်ကြိမ် vote လုပ်ရတယ် ✅
                    → Result ကို instant/scheduled ပြလို့ရတယ် ✅
```

---

## 🔧 ပြောင်းလဲရန် (3 အဆင့်)

### 1️⃣ Backend Upload:
```
📁 twork-rewards-system.php
📁 includes/class-poll-auto-run.php
```

### 2️⃣ WordPress Admin:
```
Edit Poll → Poll Mode: "Manual Session" → Update
```

### 3️⃣ Flutter App:
```bash
flutter run  # Press 'r' (hot restart)
```

---

## 👨‍💼 Winner ရွေးနည်း (Admin)

```
1. WordPress → View Results → Your Poll
2. မြင်ရမယ်: "Resolve Poll [Session: s10]"
3. Winner ရွေးပါ: [Tiger / Dragon dropdown]
4. Display ရွေးပါ:
   ○ Instant → ချက်ချင်းပြမယ်
   ○ Scheduled → Timer ပြည့်မှ ပြမယ်
5. Click: "Set Winner & Award Points"
```

---

## 🧪 Test လုပ်နည်း (5 မိနစ်)

### ✅ Checklist:

```
1. [ ] Vote လုပ်ပါ (App)
2. [ ] Log စစ်ပါ: "sessionId=s10" ပေါ်လား
3. [ ] 2 မိနစ် စောင့်ပါ (voting closes)
4. [ ] Resolve UI ပေါ်လား (Admin)
5. [ ] Winner ရွေးပါ (Admin)
6. [ ] Points ဝင်လား (Database)
7. [ ] Session အသစ် စလား (1 မိနစ် နောက်)
```

---

## 🗄️ Database Queries

### Session Resolutions စစ်ရန်:
```sql
SELECT JSON_KEYS(quiz_data->'$.session_resolutions') 
FROM 19kBefrnw_twork_engagement_items WHERE id = 280;
```

### Session Votes စစ်ရန်:
```sql
SELECT session_id, COUNT(*) as votes 
FROM 19kBefrnw_twork_user_interactions 
WHERE item_id = 280 
GROUP BY session_id;
```

### Point Transactions စစ်ရန်:
```sql
SELECT * FROM 19kBefrnw_twork_point_transactions 
WHERE order_id LIKE 'engagement:poll:280:session:%' 
ORDER BY created_at DESC LIMIT 10;
```

---

## ⚠️ အရေးကြီးတဲ့ မှတ်ချက်

### 🔴 Backend Files Upload မလုပ်ရင်:
```
❌ "Manual Session" option မပေါ်ဘူး
❌ Session resolution အလုပ်မလုပ်ဘူး
❌ Point awards မမှန်ဘူး
```

### 🔴 App Restart မလုပ်ရင်:
```
❌ session_id မပို့ဘူး
❌ "Already voted" error ရမယ်
❌ Multi-session voting အလုပ်မလုပ်ဘူး
```

### ✅ ၂ ခုလုံး လုပ်ပြီးမှ test လုပ်ပါ!

---

## 📊 Mode နှိုင်းယှဉ်ချက်

| Feature | AUTO | MANUAL_SESSION | MANUAL |
|---------|------|----------------|--------|
| **Re-voting** | ✅ | ✅ | ❌ |
| **Admin control** | ❌ | ✅ | ✅ |
| **Instant result** | ❌ | ✅ | ✅ |
| **Scheduled result** | ✅ | ✅ | ❌ |
| **Auto-reset** | ✅ | ✅ | ❌ |
| **Admin work** | 🟢 None | 🟡 Per session | 🔵 Once |

---

## 🎮 User မြင်တာ

### Voting:
```
🔥 4X Win Poll
Tiger vs Dragon
Select: [☑️ Tiger]
Amount: [2000 PNP]
⏱️ 01:30 remaining
[Submit Vote]
```

### Waiting (MANUAL_SESSION only):
```
✅ Vote လုပ်ပြီးပါပြီ
Your choice: Tiger
⏳ Waiting for results...
(Admin will announce winner)
```

### Result:
```
🏆 Winner: TIGER! 🐯
You won: +8,000 PNP 🎉
Balance: 45,000 PNP
⏱️ Next vote: 00:42
```

---

## 🔍 ပြဿနာ ဖြစ်ရင်

### "Already voted" error:
```
→ App restart လုပ်ပါ
→ Log မှာ session_id စစ်ပါ
```

### Resolve UI မပေါ်ဘူး:
```
→ Poll Mode စစ်ပါ (manual_session ဖြစ်ရမယ်)
→ Voting period ပြီးပြီလား စစ်ပါ
```

### Points မဝင်ဘူး:
```
→ Backend files upload ပြီးပြီလား
→ Debug log စစ်ပါ
```

---

## 📞 အကူအညီ

**Full Documentation:**
- 📖 `MANUAL_SESSION_POLL_GUIDE.md` (English)
- 📖 `MANUAL_SESSION_SUMMARY_MM.md` (Burmese detailed)
- 📖 `AUTO_RUN_VS_MANUAL_SESSION_VISUAL.md` (Visual comparison)
- 📖 `MANUAL_SESSION_DEPLOYMENT.md` (Deployment checklist)

**Logs:**
```bash
# Backend:
tail -f /path/to/debug.log | grep "MANUAL_SESSION"

# Frontend:
flutter logs | grep "session"
```

---

## ✅ အောင်မြင်မှု လက္ခဏာ

```
✅ Mode ပြောင်းပြီးပြီ (manual_session)
✅ App က session_id ပို့တယ် (logs မှာ မြင်ရတယ်)
✅ User က session တိုင်း vote လုပ်လို့ရတယ်
✅ Admin က Resolve UI မြင်ရတယ်
✅ Winner တွေကို points ဝင်တယ် (database မှာ ရှိတယ်)
✅ Session အသစ် auto-start ဖြစ်တယ်
```

---

**Version:** 1.0  
**Date:** 2026-03-23  
**Status:** ✅ Production Ready
