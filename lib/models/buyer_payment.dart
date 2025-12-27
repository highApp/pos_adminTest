class BuyerPayment {
  final String id;
  final String billId;
  final DateTime paymentDate;
  final String paymentType; // 'cash' or 'bank_transfer'
  final double amount;
  
  // Bank transfer fields (only if paymentType is 'bank_transfer')
  final String? accountTitle;
  final String? bankName;
  final String? accountHolderName;
  final String? referenceNumber;

  final DateTime createdAt;

  BuyerPayment({
    required this.id,
    required this.billId,
    required this.paymentDate,
    required this.paymentType,
    required this.amount,
    this.accountTitle,
    this.bankName,
    this.accountHolderName,
    this.referenceNumber,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'billId': billId,
      'paymentDate': paymentDate.toIso8601String(),
      'paymentType': paymentType,
      'amount': amount,
      'accountTitle': accountTitle,
      'bankName': bankName,
      'accountHolderName': accountHolderName,
      'referenceNumber': referenceNumber,
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
      accountTitle: map['accountTitle'],
      bankName: map['bankName'],
      accountHolderName: map['accountHolderName'],
      referenceNumber: map['referenceNumber'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }
}
