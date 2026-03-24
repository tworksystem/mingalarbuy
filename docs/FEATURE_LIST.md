# T-Work Commerce — Feature List & Issue Tracker

> **Document Purpose**: Professional feature list for Git issue tracking, sprint planning, and development reference.  
> **Format**: GitHub/GitLab style with Epics, Features, Bugs, and Enhancements.  
> **Last Updated**: March 2026

---

## Table of Contents

1. [Label & Priority Convention](#label--priority-convention)
2. [Epics](#epics)
3. [Engagement Hub & Poll System](#engagement-hub--poll-system)
4. [Points & Rewards System](#points--rewards-system)
5. [Authentication & Security](#authentication--security)
6. [E-Commerce Core](#e-commerce-core)
7. [Wallet & Payments](#wallet--payments)
8. [Infrastructure & DevOps](#infrastructure--devops)
9. [Technical Debt & Refactoring](#technical-debt--refactoring)

---

## Label & Priority Convention

| Label       | Color  | Use Case                                                |
|------------|--------|---------------------------------------------------------|
| `epic`     | purple | Large feature grouping; spans multiple sprints          |
| `feature`  | blue   | New functionality                                       |
| `enhancement` | cyan | Improvement to existing feature                         |
| `bug`      | red    | Defect or incorrect behavior                            |
| `fix`      | orange | Resolution of bug or regression                         |
| `backend`  | gray   | WordPress / PHP / REST API                              |
| `frontend` | green  | Flutter / Dart / UI                                     |
| `documentation` | brown | Docs, guides, README                               |

| Priority | Level | Description                                   |
|----------|-------|-----------------------------------------------|
| P0       | Critical | Blocks release or core user flow           |
| P1       | High     | Important; should be in current sprint      |
| P2       | Medium   | Valuable; plan for next sprint              |
| P3       | Low      | Nice to have; backlog                       |

---

## Epics

### Epic #1: Engagement Hub & Auto-Run Poll

**Labels**: `epic`, `engagement`, `poll`, `frontend`, `backend`  
**Status**: In Progress  
**Priority**: P1  
**Summary**: End-to-end Auto-Run Poll lifecycle with point validation, confirmation flow, and time-based state management.

---

### Epic #2: Points & Rewards (Rewards-Only Mode)

**Labels**: `epic`, `points`, `rewards`, `backend`  
**Status**: In Progress  
**Priority**: P1  
**Summary**: Operate points and poll deductions using only `twork-rewards-system` (no dependency on T-Work Points System plugin).

---

### Epic #3: Offline-First & Sync Architecture

**Labels**: `epic`, `offline`, `sync`, `architecture`  
**Status**: Stable  
**Priority**: P2  
**Summary**: Offline queue, background sync, and connectivity handling across the app.

---

## Engagement Hub & Poll System

### FEAT-101: Auto-Run Poll Lifecycle Integration

| Field | Value |
|-------|-------|
| **Type** | Feature |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `feature`, `engagement`, `poll`, `frontend`, `backend` |

**Description**  
Implement time-based Auto-Run Poll lifecycle: `ACTIVE` (voting) → `SHOWING_RESULTS` → 5s countdown → next cycle. State is lazy-evaluated via REST API; no WP-Cron polling.

**Acceptance Criteria**  
- [ ] `GET /wp-json/twork/v1/poll/state/{poll_id}` returns `state`, `current_session_id`, `ends_at`, `poll_duration`, `result_display_duration`, `mode`  
- [ ] `GET /wp-json/twork/v1/poll/results/{poll_id}/{session_id}` returns vote counts and percentages per session  
- [ ] Flutter `AutoRunPollWidget` fetches poll state and renders ACTIVE / SHOWING_RESULTS / COUNTDOWN states  
- [ ] Timer re-evaluates every second against `ends_at`  
- [ ] Countdown 10–9–8… shown when ≤10s to `ends_at`  
- [ ] Engagement provider auto-poll pauses during results and countdown phases  

**Affected Files**  
- `lib/widgets/auto_run_poll_widget.dart`  
- `lib/services/engagement_service.dart`  
- `wp-content/plugins/twork-rewards-system/twork-rewards-system.php`  
- `docs/POLL_AUTO_RUN_INTEGRATION.md`

---

### FEAT-102: Poll Point Validation & Confirmation Flow

| Field | Value |
|-------|-------|
| **Type** | Feature |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `feature`, `engagement`, `poll`, `points`, `frontend` |

**Description**  
Pre-submit validation: selection check, total cost (base cost × selected options), balance check. Confirmation dialogs: insufficient balance and spend confirmation before API submit.

**Acceptance Criteria**  
- [ ] User selects option(s) → “ကစားမည်” → validation runs (selection, cost, balance)  
- [ ] If insufficient balance: show friendly message (e.g., “Point မလောက်ပါ လက်ကျန်: X, လိုအပ်ချက်: Y”)  
- [ ] If sufficient: show confirmation (“သင့်လက်ကျန်: X Point, နှုတ်မည့်: Y Point”)  
- [ ] User confirms → POST engagement interact with `selected_option_ids`  
- [ ] Balance display uses `points_balance`, `my_points`, `my_point` from user meta / custom fields (comma-safe parsing)  

**Affected Files**  
- `lib/widgets/engagement_carousel.dart` (`_onPlayPressed`, `_submitVote`, `_balanceFromCustomFields`, `_confirmedBalanceForSubmit`)  
- `lib/widgets/auto_run_poll_widget.dart`  
- `lib/providers/point_provider.dart`  

---

### FEAT-103: Poll Vote Deduction (Rewards-Only)

| Field | Value |
|-------|-------|
| **Type** | Bug / Enhancement |
| **Priority** | P0 |
| **Status** | Implemented |
| **Labels** | `bug`, `fix`, `backend`, `points`, `rewards` |

**Description**  
When only `twork-rewards-system` is used (T-Work Points System plugin inactive), poll vote cost must deduct from actual balance. Previously meta (`points_balance`, `my_points`, `my_point`) was not updated, so app showed stale balance.

**Acceptance Criteria**  
- [ ] Poll vote submits successfully  
- [ ] Transaction created in `twork_point_transactions` (type `redeem`)  
- [ ] Meta `points_balance`, `my_points`, `my_point` updated with new balance  
- [ ] App My PNP / profile shows correct post-deduction balance  
- [ ] `/wp-json/wp/v2/users/me` returns updated `points_balance`  

**Implementation Notes**  
- Use `sync_user_points($user_id, -$total_cost, $order_id, $description, true)` in rewards plugin poll deduction branch  
- Order ID format: `engagement:poll_cost:{item_id}:{timestamp}`  
- Description: `Poll entry cost: {title} (-{points} points)`  

**Affected Files**  
- `wp-content/plugins/twork-rewards-system/twork-rewards-system.php` (poll deduction branch in `rest_engagement_interact`)  
- `wp-content/plugins/twork-rewards-system/includes/class-poll-pnp.php`  

---

### FEAT-104: Poll Balance Check (Multi-Source Fallback)

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `backend`, `points` |

**Description**  
Balance check for poll cost must read from multiple meta keys when primary source (Points System / PNP) returns 0. Prevents “လက်ကျန် 0” when balance exists in `points_balance`, `my_points`, or `my_point`.

**Acceptance Criteria**  
- [ ] When Points System inactive: read `_user_pnp_balance` via `TWork_Poll_PNP::get_user_pnp()`  
- [ ] If balance still ≤ 0: defensive read from `points_balance`, `my_points`, `my_point`, `_user_pnp_balance` and use max  
- [ ] Use same `$balance` for both insufficient check and deduction  

**Affected Files**  
- `wp-content/plugins/twork-rewards-system/twork-rewards-system.php`  

---

### FEAT-105: Session-Scoped Poll Votes

| Field | Value |
|-------|-------|
| **Type** | Feature |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `feature`, `backend`, `poll` |

**Description**  
AUTO_RUN polls use session-based voting. Each cycle has unique `session_id`; votes scoped per `(user_id, item_id, session_id)`.

**Acceptance Criteria**  
- [ ] `user_interactions` table has `session_id` column  
- [ ] Unique constraint: `(user_id, item_id, session_id)`  
- [ ] `rest_engagement_interact` accepts and stores `session_id`  
- [ ] `rest_poll_results_by_session` filters by `session_id`  
- [ ] Flutter sends `session_id` from poll state response  

**Affected Files**  
- `wp-content/plugins/twork-rewards-system/twork-rewards-system.php`  
- `lib/services/engagement_service.dart`  
- `lib/widgets/auto_run_poll_widget.dart`  

---

### FEAT-106: Random Winner Fallback

| Field | Value |
|-------|-------|
| **Type** | Feature |
| **Priority** | P2 |
| **Status** | Implemented |
| **Labels** | `feature`, `frontend`, `poll` |

**Description**  
When backend does not specify winning option, client picks random winner among options with highest votes for display.

**Affected Files**  
- `lib/widgets/engagement_carousel.dart`  
- `lib/widgets/auto_run_poll_widget.dart`  

---

## Points & Rewards System

### FEAT-201: Single-Source Balance (Transactions Table)

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `backend`, `points` |

**Description**  
Balance is calculated from `twork_point_transactions`; meta fields (`points_balance`, `my_points`, `my_point`) are cache only and updated by `sync_user_points()`.

**Acceptance Criteria**  
- [ ] `calculate_points_balance_from_transactions()` is authoritative  
- [ ] Poll deduction creates `redeem` transaction  
- [ ] Meta updated after each transaction  

**Affected Files**  
- `wp-content/plugins/twork-rewards-system/twork-rewards-system.php`  
- `sync_user_points()`  

---

### FEAT-202: Point Provider Balance Fallback (Auth Custom Fields)

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `frontend`, `points` |

**Description**  
When `PointProvider.currentBalance == 0` but user has balance in auth custom fields, use `_balanceFromCustomFields()` for confirmation dialog and submit validation.

**Acceptance Criteria**  
- [ ] Read `my_point`, `my_points`, `My Point Value`, `points_balance` (comma-safe)  
- [ ] Use for pre-submit balance display and insufficient-balance message  
- [ ] Take max of PointProvider, AuthProvider custom fields, and confirmed balance  

**Affected Files**  
- `lib/widgets/engagement_carousel.dart`  

---

### FEAT-203: Insufficient Balance Message (Server Balance 0)

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P2 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `frontend`, `ux` |

**Description**  
When server returns `insufficient_balance` with `balance: 0` but client had confirmed balance (e.g. 18,200), show friendlier message: “Server မှာ balance မတွေ့သေးပါ (သင့်လက်ကျန်: X, လိုအပ်ချက်: Y)”.

**Affected Files**  
- `lib/widgets/engagement_carousel.dart`  

---

### FEAT-204: Point Transaction Sorting & Pagination

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P2 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `frontend`, `backend` |

**Description**  
Transactions ordered by date (newest first). Support `orderby`, `order`, `page`, `per_page` for API and UI.

**Affected Files**  
- `lib/models/point_transaction.dart`  
- `lib/services/point_service.dart`  
- `wp-content/plugins/twork-rewards-system/twork-rewards-system.php`  

---

## Authentication & Security

### FEAT-301: Token Caching & Synchronization

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `auth`, `frontend` |

**Description**  
Synchronous token caching for immediate access. `ensureTokenSynchronized()` for refresh. Account switching clears caches across providers.

**Affected Files**  
- `lib/services/auth_service.dart`  
- `lib/providers/auth_provider.dart`  

---

### FEAT-302: Push Notification User Verification

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `security`, `notifications` |

**Description**  
Background notifications verify current user to prevent cross-user notification display.

**Affected Files**  
- `lib/services/push_notification_service.dart`  
- `wp-content/plugins/twork-fcm-notify/`  

---

## E-Commerce Core

### FEAT-401: Product Catalog & Search

| Field | Value |
|-------|-------|
| **Type** | Feature |
| **Priority** | P2 |
| **Status** | Stable |
| **Labels** | `feature`, `ecommerce`, `frontend` |

**Description**  
Product listing, filters, search, category navigation, wishlist.

---

### FEAT-402: Shopping Cart & Checkout

| Field | Value |
|-------|-------|
| **Type** | Feature |
| **Priority** | P2 |
| **Status** | Stable |
| **Labels** | `feature`, `ecommerce` |

**Description**  
Cart, quantity management, checkout flow, address management.

---

## Wallet & Payments

### FEAT-501: Wallet Balance & P2P Transfer

| Field | Value |
|-------|-------|
| **Type** | Feature |
| **Priority** | P2 |
| **Status** | Stable |
| **Labels** | `feature`, `wallet` |

**Description**  
Wallet balance, send money, request money, transaction history.

---

## Infrastructure & DevOps

### FEAT-601: Engagement Feed Auto-Poll

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P2 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `frontend` |

**Description**  
Near real-time engagement feed via polling. Force refresh and debouncing.

**Affected Files**  
- `lib/providers/engagement_provider.dart`  
- `lib/screens/main/main_page.dart`  

---

### FEAT-602: User Account Switching Handling

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P1 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `auth`, `points` |

**Description**  
On account switch: clear point cache, engagement cache, reload balance, prevent stale data.

**Affected Files**  
- `lib/providers/point_provider.dart`  
- `lib/providers/engagement_provider.dart`  
- `lib/providers/auth_provider.dart`  

---

### FEAT-603: Network Utilities

| Field | Value |
|-------|-------|
| **Type** | Enhancement |
| **Priority** | P3 |
| **Status** | Implemented |
| **Labels** | `enhancement`, `infrastructure` |

**Description**  
Shared network helpers, retry logic, error handling.

**Affected Files**  
- `lib/utils/network_utils.dart`  

---

## Technical Debt & Refactoring

### DEBT-01: Plugin Consolidation (twork-points-system)

| Field | Value |
|-------|-------|
| **Type** | Refactor |
| **Priority** | P2 |
| **Status** | Deferred |
| **Labels** | `refactor`, `backend` |

**Description**  
Project uses only `twork-rewards-system`; `twork-points-system` plugin removed or deprecated. Ensure no code paths depend on Points System for poll/balance when rewards-only mode.

---

### DEBT-02: Engagement Carousel Complexity

| Field | Value |
|-------|-------|
| **Type** | Refactor |
| **Priority** | P3 |
| **Status** | Backlog |
| **Labels** | `refactor`, `frontend` |

**Description**  
`engagement_carousel.dart` is large. Consider extracting poll card, quiz card, banner card into separate widgets.

---

### DEBT-03: WordPress Plugin PHP Lint Environment

| Field | Value |
|-------|-------|
| **Type** | Infrastructure |
| **Priority** | P3 |
| **Status** | Backlog |
| **Labels** | `infrastructure`, `ci` |

**Description**  
IDE linter reports “unknown function” for WordPress APIs. Add PHP stubs or configure IDE for WordPress context.

---

## Quick Reference: Current Work in Progress (Uncommitted)

| Area | Status | Files |
|------|--------|-------|
| Poll deduction (rewards-only) | Fixed | `twork-rewards-system.php` |
| Balance fallback in carousel | Implemented | `engagement_carousel.dart` |
| Auto-run poll widget | In use | `auto_run_poll_widget.dart` |
| Auth & point providers | Enhanced | `auth_service.dart`, `point_service.dart` |
| Plugin removal | Pending | `twork-points-system` deleted, `twork-spin-wheel` deleted |

---

## Issue Template (Copy for New Issues)

```markdown
### FEAT-XXX: [Title]

| Field | Value |
|-------|-------|
| **Type** | Feature / Bug / Enhancement |
| **Priority** | P0–P3 |
| **Status** | Open / In Progress / Done |
| **Labels** | `label1`, `label2` |

**Description**
[What and why]

**Acceptance Criteria**
- [ ] Criterion 1
- [ ] Criterion 2

**Affected Files**
- path/to/file

**Related Issues**
- FEAT-XXX
```

---

*Document maintained for T-Work Commerce / Mingalarbuy development.*
