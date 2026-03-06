# Performance Guide – Why the app can feel slow & what was fixed

You’re on **Firebase Blaze**. Slowness usually comes from **too many Firestore reads** and **heavy UI** (dashboard). Below is what was found and what was changed.

---

## What was fixed (already done)

### 1. Dashboard: date-range queries instead of full collections
- **Before:** Dashboard used `getSalesStream()`, `getExpensesStream()`, `getBorrowsStream()` → **all sales, all expenses, all borrows** were read whenever anything changed.
- **After:** Dashboard now uses:
  - `getSalesByDateRange(effectiveStartDate, effectiveEndDate)`
  - `getExpensesByDateRange(...)`
  - `getBorrowsByDateRange(...)`
- **Effect:** For “Today” or “Last 7 days” you only read documents in that range. This can cut dashboard reads by **80–95%** depending on data size.

### 2. Recent sales: limit 5
- **Before:** “Recent sales” used `getSalesStream()` and then `.take(5)` in the UI → still loaded **all** sales.
- **After:** Uses `getRecentSalesStream(limit: 5)` so Firestore only returns 5 docs.
- **Effect:** Far fewer reads on the dashboard.

---

## Remaining causes of slowness (what to watch)

### 1. Dashboard: many nested StreamBuilders
- The dashboard still has **11 nested StreamBuilders + 1 FutureBuilder** (sales, expenses, borrows, unpaid, borrowProfit, realProfit, sellerOrders, balance, creditBalance, creditReductions, periodCreditReductions).
- **Why it hurts:** Every time any of these streams emits, the whole tree can rebuild. Many streams → many rebuilds.
- **Already mitigated:** Seller service uses `_dashboardThrottle` (25 seconds) so profit/unpaid streams don’t fire on every doc change.
- **Optional improvement:** Combine these into one stream (e.g. with `rxdart`’s `CombineLatestStream`) and a single `StreamBuilder` so you get one rebuild per “tick” instead of a deep rebuild chain.

### 2. Seller service: full collection reads on each throttle tick
- `getRealProfitFromPaidStreamByDateRange` and `getBorrowProfitStreamByDateRange` listen to `sales` and `seller_history`, and on each emission they do:
  - `_firestore.collection('sales').get()`
  - `_firestore.collection('seller_history').get()`
- So **every 25 seconds** (and on any change) they re-read **all** sales and **all** seller_history, then filter by date in memory.
- **Improvement:** Use Firestore **date-range queries** (e.g. `where('createdAt', ...)` / `where('saleDate', ...)`) so only docs in the selected range are read. You may need composite indexes in Firebase Console.

### 3. Products: no limit on product stream
- `getProductsStream()` loads **all** products. With thousands of products, that’s slow and expensive.
- **Improvement:**  
  - For POS/product list: use **pagination** (e.g. `limit(50)` and “load more”) or load by category.  
  - Keep “all products” only where you really need it, and consider caching (you already have 60s cache for search).

### 4. Buyer bills & seller history: multiple streams
- Screens like `buyer_bills_screen` and `seller_history_screen` use several `StreamBuilder`s and sometimes full-collection snapshots.
- **Improvement:** Prefer **date-range or limited** queries where possible; avoid listening to entire collections if the UI only needs a subset.

### 5. Firestore persistence (cache)
- Enabling **offline persistence** lets Firestore serve repeated reads from local cache, which reduces latency and can reduce read cost.
- You can enable it once after `Firebase.initializeApp()` (see example in next section).

---

## Optional: enable Firestore cache (recommended)

In `main.dart`, after `Firebase.initializeApp(...)`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(...);

  // Use cache for faster repeat reads and fewer billable reads
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const MyApp());
}
```

- **persistenceEnabled:** Uses local cache when supported (e.g. web and mobile).
- **cacheSizeBytes:** `CACHE_SIZE_UNLIMITED` avoids evicting cache too aggressively (Blaze plan can handle it).

---

## Firebase Console checks (Blaze)

1. **Firestore → Usage:** See read/write volume. After the dashboard changes, you should see fewer reads when switching dates or leaving the dashboard open.
2. **Firestore → Indexes:** Add any composite indexes suggested in the app (e.g. for date-range queries on `sales`, `seller_history`, `expenses`, `borrows`).
3. **Performance / Network:** If you use Firebase Performance, check for slow screens or high network time.

---

## Summary

- **Done:** Dashboard uses **date-range** streams for sales/expenses/borrows and **limit 5** for recent sales. This should make the dashboard much lighter and cheaper.
- **Next:** Add date-range queries in seller service profit streams, enable Firestore cache, and consider combining dashboard streams or paginating products if you still see slowness or high read counts.
