class ZakatRecord {
  final String id;
  final double wealthAmount;
  final double zakatAmount;
  final DateTime date;
  final String? notes;

  ZakatRecord({
    required this.id,
    required this.wealthAmount,
    required this.zakatAmount,
    required this.date,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'wealthAmount': wealthAmount,
      'zakatAmount': zakatAmount,
      'date': date.toIso8601String(),
      'notes': notes,
    };
  }

  factory ZakatRecord.fromMap(Map<String, dynamic> map) {
    return ZakatRecord(
      id: map['id'] ?? '',
      wealthAmount: (map['wealthAmount'] ?? 0).toDouble(),
      zakatAmount: (map['zakatAmount'] ?? 0).toDouble(),
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
      notes: map['notes']?.toString(),
    );
  }
}
