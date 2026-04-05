/// Store name on printed / PDF receipts (thermal + PDF use the same text).
class ReceiptBranding {
  ReceiptBranding._();

  static const String storeName = "AR's TRADERS";

  /// Thermal line (include newline for ESC/POS).
  static String get storeNameLine => '$storeName\n';
}
