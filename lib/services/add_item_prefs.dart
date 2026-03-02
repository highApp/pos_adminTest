import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists last-used and recent categories for Add Item so user doesn't have to select every time.
/// Also stores draft bill items when user leaves Create Bill without saving.
class AddItemPrefs {
  static const _keyLast = 'add_item_last_category';
  static const _keyRecent = 'add_item_recent_categories';
  static const _keyDraftItems = 'buyer_bill_draft_items';
  static const _maxRecent = 5;

  static Future<String?> getLastCategory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLast);
  }

  static Future<void> saveCategory(String category) async {
    if (category.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLast, category.trim());
    final recent = await getRecentCategories();
    final updated = [category.trim(), ...recent.where((c) => c != category.trim())].take(_maxRecent).toList();
    await prefs.setString(_keyRecent, jsonEncode(updated));
  }

  static Future<List<String>> getRecentCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRecent);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      return list?.map((e) => e.toString()).where((s) => s.isNotEmpty).toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Save draft items (list of item maps) when user leaves Create Bill without saving.
  static Future<void> saveDraftItems(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_keyDraftItems);
      return;
    }
    await prefs.setString(_keyDraftItems, jsonEncode(items));
  }

  /// Get draft items if any; returns null if none.
  static Future<List<Map<String, dynamic>>?> getDraftItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDraftItems);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null || list.isEmpty) return null;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDraftItems);
  }
}
