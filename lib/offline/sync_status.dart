/// Row-level sync state for local mirrors of server entities.
///
/// Use on products, customers, sales, expenses, stock rows, etc.
abstract final class SyncStatus {
  static const int pending = 0;
  static const int synced = 1;
  static const int failed = 2;

  static bool isPending(int v) => v == pending;
  static bool isSynced(int v) => v == synced;
  static bool isFailed(int v) => v == failed;
}
