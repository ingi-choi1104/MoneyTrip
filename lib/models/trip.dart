class Trip {
  final int? id;
  final String name;
  final String country;
  final DateTime startDate;
  final DateTime endDate;
  final String currency;
  final double budget;
  final bool isActive;

  Trip({
    this.id,
    required this.name,
    required this.country,
    required this.startDate,
    required this.endDate,
    required this.currency,
    this.budget = 0,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'country': country,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'currency': currency,
      'budget': budget,
      'isActive': isActive ? 1 : 0,
    };
  }

  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      id: map['id'],
      name: map['name'],
      country: map['country'],
      startDate: DateTime.parse(map['startDate']),
      endDate: DateTime.parse(map['endDate']),
      currency: map['currency'],
      budget: map['budget'],
      isActive: map['isActive'] == 1,
    );
  }

  Trip copyWith({
    int? id,
    String? name,
    String? country,
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
    double? budget,
    bool? isActive,
  }) {
    return Trip(
      id: id ?? this.id,
      name: name ?? this.name,
      country: country ?? this.country,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      currency: currency ?? this.currency,
      budget: budget ?? this.budget,
      isActive: isActive ?? this.isActive,
    );
  }

  int get durationInDays {
    return endDate.difference(startDate).inDays + 1;
  }
}
