class BuyerPayment {
  final String id;
  final String billId;
  final DateTime paymentDate;
  final String paymentType; // 'cash' or 'bank_transfer'
  final double amount;
  
  /// Short 4-digit ID (e.g. PAY-1234) shown on success and in payment history
  final String? paymentNumber;
  
  /// Groups payments made in same transaction (e.g. one amount split across multiple bills)
  final String? batchId;
  
  // Bank transfer fields (only if paymentType is 'bank_transfer')
  final String? accountTitle;
  final String? bankName;
  final String? accountHolderName;
  final String? referenceNumber;

  /// Optional reference for any payment type (receipt #, slip id, note). Bank transfers also set [referenceNumber].
  final String? reference;

  final DateTime createdAt;

  BuyerPayment({
    required this.id,
    required this.billId,
    required this.paymentDate,
    required this.paymentType,
    required this.amount,
    this.paymentNumber,
    this.batchId,
    this.accountTitle,
    this.bankName,
    this.accountHolderName,
    this.referenceNumber,
    this.reference,
    required this.createdAt,
  });

  /// Receipt / slip / transaction id for display (prefers [reference], then [referenceNumber]).
  String? get effectiveReference {
    final r = reference?.trim();
    if (r != null && r.isNotEmpty) return r;
    final n = referenceNumber?.trim();
    if (n != null && n.isNotEmpty) return n;
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'billId': billId,
      'paymentDate': paymentDate.toIso8601String(),
      'paymentType': paymentType,
      'amount': amount,
      'paymentNumber': paymentNumber,
      'batchId': batchId,
      'accountTitle': accountTitle,
      'bankName': bankName,
      'accountHolderName': accountHolderName,
      'referenceNumber': referenceNumber,
      'reference': reference,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory BuyerPayment.fromMap(Map<String, dynamic> map) {
    return BuyerPayment(
      id: map['id'] ?? '',
      billId: map['billId'] ?? '',
      paymentDate: map['paymentDate'] != null
          ? DateTime.parse(map['paymentDate'])
          : DateTime.now(),
      paymentType: map['paymentType'] ?? 'cash',
      amount: (map['amount'] ?? 0).toDouble(),
      paymentNumber: map['paymentNumber'],
      batchId: map['batchId'],
      accountTitle: map['accountTitle'],
      bankName: map['bankName'],
      accountHolderName: map['accountHolderName'],
      referenceNumber: map['referenceNumber'],
      reference: map['reference'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }
}
