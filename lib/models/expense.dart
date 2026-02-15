class Expense {
  final int? id;
  final int tripId;
  final double amount;
  final String category;
  final String paymentMethod; // 'cash' or 'card'
  final DateTime date;
  final String? title; // 제목 (선택사항)
  final String? note;
  final String? imagePath;
  final double? latitude; // 위도 (선택사항)
  final double? longitude; // 경도 (선택사항)
  final String? locationName; // 위치 이름 (선택사항)
  final String? originalCurrency; // 입력 시 선택한 통화
  final double? originalAmount; // 입력 시 원래 금액

  Expense({
    this.id,
    required this.tripId,
    required this.amount,
    required this.category,
    required this.paymentMethod,
    required this.date,
    this.title,
    this.note,
    this.imagePath,
    this.latitude,
    this.longitude,
    this.locationName,
    this.originalCurrency,
    this.originalAmount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'amount': amount,
      'category': category,
      'paymentMethod': paymentMethod,
      'date': date.toIso8601String(),
      'title': title,
      'note': note,
      'imagePath': imagePath,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'originalCurrency': originalCurrency,
      'originalAmount': originalAmount,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      tripId: map['tripId'],
      amount: map['amount'],
      category: map['category'],
      paymentMethod: map['paymentMethod'],
      date: DateTime.parse(map['date']),
      title: map['title'],
      note: map['note'],
      imagePath: map['imagePath'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      locationName: map['locationName'],
      originalCurrency: map['originalCurrency'],
      originalAmount: map['originalAmount'],
    );
  }

  Expense copyWith({
    int? id,
    int? tripId,
    double? amount,
    String? category,
    String? paymentMethod,
    DateTime? date,
    String? title,
    String? note,
    String? imagePath,
    double? latitude,
    double? longitude,
    String? locationName,
    String? originalCurrency,
    double? originalAmount,
  }) {
    return Expense(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      date: date ?? this.date,
      title: title ?? this.title,
      note: note ?? this.note,
      imagePath: imagePath ?? this.imagePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      originalCurrency: originalCurrency ?? this.originalCurrency,
      originalAmount: originalAmount ?? this.originalAmount,
    );
  }
}
