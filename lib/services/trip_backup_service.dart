import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../models/trip.dart';
import '../models/expense.dart';
import '../models/income.dart';

class TripBackupService {
  static Future<void> exportTrip({
    required Trip trip,
    required List<Expense> expenses,
    required List<Income> incomes,
  }) async {
    final data = {
      'version': 1,
      'type': 'single_trip',
      'trips': [_buildTripData(trip, expenses, incomes)],
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    await _shareJsonFile(jsonStr, '${trip.name}_backup');
  }

  static Future<void> exportAllTrips({
    required List<Trip> trips,
    required Map<int, List<Expense>> expensesMap,
    required Map<int, List<Income>> incomesMap,
  }) async {
    final data = {
      'version': 1,
      'type': 'all_trips',
      'trips': trips
          .map((t) => _buildTripData(t, expensesMap[t.id] ?? [], incomesMap[t.id] ?? []))
          .toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    await _shareJsonFile(jsonStr, 'all_trips_backup');
  }

  static Map<String, dynamic> _buildTripData(
    Trip trip,
    List<Expense> expenses,
    List<Income> incomes,
  ) {
    return {
      'trip': {
        'name': trip.name,
        'country': trip.country,
        'startDate': trip.startDate.toIso8601String(),
        'endDate': trip.endDate.toIso8601String(),
        'currency': trip.currency,
        'budget': trip.budget,
      },
      'expenses': expenses
          .map((e) => {
                'amount': e.amount,
                'category': e.category,
                'paymentMethod': e.paymentMethod,
                'date': e.date.toIso8601String(),
                'title': e.title,
                'note': e.note,
                'latitude': e.latitude,
                'longitude': e.longitude,
                'locationName': e.locationName,
                'originalCurrency': e.originalCurrency,
                'originalAmount': e.originalAmount,
              })
          .toList(),
      'incomes': incomes
          .map((i) => {
                'amount': i.amount,
                'date': i.date.toIso8601String(),
                'note': i.note,
              })
          .toList(),
    };
  }

  static Future<void> _shareJsonFile(String json, String name) async {
    final dir = await getTemporaryDirectory();
    final filename = '${name}_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(json);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: '여행 데이터 백업',
    );
  }

  /// JSON 파일을 불러와 여행 데이터 목록을 반환합니다.
  /// 반환값: trips 배열 (각 원소는 trip, expenses, incomes 포함)
  static Future<List<Map<String, dynamic>>?> importTrips() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return null;

    final pickedFile = result.files.first;
    String jsonStr;

    if (pickedFile.path != null) {
      jsonStr = await File(pickedFile.path!).readAsString();
    } else if (pickedFile.bytes != null) {
      jsonStr = utf8.decode(pickedFile.bytes!);
    } else {
      return null;
    }

    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw Exception('지원하지 않는 백업 파일 형식입니다 (version: ${data['version']})');
    }

    final trips = data['trips'] as List<dynamic>;
    return trips.cast<Map<String, dynamic>>();
  }
}
