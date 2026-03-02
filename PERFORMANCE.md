# Performance notes (why the app can feel slow on Blaze)

Blaze plan gives you more quota; it does **not** by itself make the app faster. Slowness usually comes from **how much data is read** and **how often**.

## Main causes in this app

### 1. Dashboard: many real-time streams at once
The dashboard subscribes to **10+ Firestore streams** at the same time:
- All sales, expenses, borrows, seller orders, balance entries
- Total unpaid sales (all `seller_history`), borrow profit, real profit, credit balance, etc.

Each stream uses `.snapshots()` and re-runs when **any** document in that collection changes. So one change can trigger many re-reads and rebuilds.

**What you can do:**
- Avoid leaving the dashboard open on a tab you’re not using.
- For “Borrow profit” / “Real profit” type stats, consider caching for 1–2 minutes instead of strict real-time.

### 2. Full collection reads (no filters)
Some logic loads **entire collections** then filters in memory, for example:
- **Seller service:** `getTotalUnpaidSales()`, `getTotalUnpaidSalesByDateRange()` read all `seller_history` docs.
- **Product search:** `searchProducts()` loads all products then filters by name/barcode in the app.
- **Borrow/real profit streams:** Read all `seller_history` and all `sales` to compute totals.

The more documents you have in `sales`, `seller_history`, `products`, the slower these become and the more reads you use.

**What you can do:**
- Add Firestore **indexes** for the queries you use (Firebase Console → Firestore → Indexes).
- For product search, consider a **search index** (e.g. Algolia, Typesense) or at least a `.limit()` for the initial load.
- For date-range stats, prefer Firestore `where('date', '>=', start).where('date', '<=', end)` (with a composite index) instead of loading the whole collection.

### 3. Debug logging (reduced in code)
`SellerService` had a lot of `debugPrint` on hot paths (e.g. borrow profit, unpaid sales). Those are now behind a flag so they don’t run in normal use, which reduces I/O and CPU a bit.

## Quick checks in Firebase Console

1. **Firestore → Usage**  
   See read/write volume. High reads per second = lots of listeners or heavy queries.

2. **Firestore → Indexes**  
   Add composite indexes for any query that the console suggests (e.g. `sellerId` + `createdAt`, or date range queries).

3. **Reduce listeners**  
   Don’t keep many tabs open on the admin app; each tab keeps its own listeners and reads.

## Summary

- **Blaze** = higher limits and you can scale; it does **not** automatically optimize reads.
- **Actual speed** depends on: number of documents read, number of active listeners, and doing work in memory (e.g. filtering big lists).
- **Improvements:** fewer full-collection reads, more indexed queries, fewer simultaneous streams, and optional caching for heavy stats.
