class Income {
  final int? id;
  final int tripId;
  final double amount;
  final DateTime date;
  final String? note;

  Income({
    this.id,
    required this.tripId,
    required this.amount,
    required this.date,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'amount': amount,
      'date': date.toIso8601String(),
      'note': note,
    };
  }

  factory Income.fromMap(Map<String, dynamic> map) {
    return Income(
      id: map['id'],
      tripId: map['tripId'],
      amount: map['amount'],
      date: DateTime.parse(map['date']),
      note: map['note'],
    );
  }
}
