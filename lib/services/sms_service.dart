import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:another_telephony/telephony.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';
import '../models/trip.dart';
import 'sms_parser_service.dart';

/// 백그라운드 SMS 수신 핸들러 — 반드시 최상위 함수여야 함
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  try {
    debugPrint('[SMS-BG] 백그라운드 문자 수신');
    final body = message.body;
    if (body == null || body.isEmpty) return;

    final dbHelper = DatabaseHelper.instance;

    final isEnabled = await dbHelper.getSetting('sms_auto_register');
    if (isEnabled != 'true') return;

    final result = SmsParserService.parse(body);
    if (result == null) return;

    final smsHash = body.hashCode.toRadixString(16);
    final alreadyProcessed = await dbHelper.getSetting('sms_$smsHash');
    if (alreadyProcessed == 'true') return;

    final trips = await dbHelper.getAllTrips();
    final dateOnly = DateTime(result.date.year, result.date.month, result.date.day);
    Trip? matchingTrip;
    for (final trip in trips) {
      final start = DateTime(trip.startDate.year, trip.startDate.month, trip.startDate.day);
      final end = DateTime(trip.endDate.year, trip.endDate.month, trip.endDate.day);
      if (!dateOnly.isBefore(start) && !dateOnly.isAfter(end)) {
        matchingTrip = trip;
        break;
      }
    }
    if (matchingTrip == null) return;

    final expense = Expense(
      tripId: matchingTrip.id!,
      amount: result.amount,
      category: '기타',
      paymentMethod: 'card',
      date: result.date,
      title: result.storeName,
      note: '[SMS 자동등록]',
    );
    await dbHelper.insertExpense(expense);
    await dbHelper.saveSetting('sms_$smsHash', 'true');

    final popupEnabled = await dbHelper.getSetting('popup_notification');
    if (popupEnabled == 'true') {
      try {
        await _showBackgroundNotification(result.storeName, result.amount);
      } catch (e) {
        debugPrint('[SMS-BG] 알림 표시 실패: $e');
      }
    }
  } catch (e) {
    debugPrint('[SMS-BG] 백그라운드 처리 오류: $e');
  }
}

Future<void> _showBackgroundNotification(String? storeName, double amount) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidSettings));

  final amountStr = '${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';

  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    '지출 자동 등록',
    '${storeName ?? '(매장명 없음)'} $amountStr',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'sms_expense',
        '문자 자동 등록',
        channelDescription: '카드 결제 문자를 자동으로 지출 등록합니다',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

class SmsService {
  static final SmsService instance = SmsService._();
  SmsService._();

  final Telephony _telephony = Telephony.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  bool _listenerRegistered = false;
  int _lastCheckTime = 0;

  final _expenseController = StreamController<Expense>.broadcast();
  Stream<Expense> get onExpenseCreated => _expenseController.stream;

  /// 최초 설정 토글 시 호출: 권한 요청 → 초기화 (1회만)
  Future<bool> requestAndInitialize() async {
    if (_initialized) return true;

    try {
      bool? granted;
      try {
        granted = await _telephony.requestPhoneAndSmsPermissions;
      } catch (e) {
        debugPrint('[SMS] 권한 요청 중 오류: $e');
        return false;
      }

      if (granted != true) {
        debugPrint('[SMS] 권한 거부됨');
        return false;
      }

      await _setupAfterPermission();
      return true;
    } catch (e) {
      debugPrint('[SMS] requestAndInitialize 실패: $e');
      return false;
    }
  }

  /// 앱 시작 시 호출: 이미 권한이 있으면 리스너만 등록
  Future<bool> initializeIfPermitted() async {
    if (_initialized) return true;

    try {
      final granted = await _telephony.requestPhoneAndSmsPermissions;
      if (granted != true) {
        debugPrint('[SMS] 권한 없음 — 리스너 미등록');
        return false;
      }

      await _setupAfterPermission();
      return true;
    } catch (e) {
      debugPrint('[SMS] initializeIfPermitted 실패: $e');
      return false;
    }
  }

  /// 권한 획득 후 공통 초기화 (1회만 실행)
  Future<void> _setupAfterPermission() async {
    // 알림 초기화 (실패해도 계속)
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _notifications.initialize(
        const InitializationSettings(android: androidSettings),
      );
    } catch (e) {
      debugPrint('[SMS] 알림 초기화 실패: $e');
    }

    // 마지막 확인 시각 로드
    final saved = await _dbHelper.getSetting('sms_last_check');
    if (saved != null) {
      _lastCheckTime = int.tryParse(saved) ?? DateTime.now().millisecondsSinceEpoch;
    } else {
      _lastCheckTime = DateTime.now().millisecondsSinceEpoch;
      await _dbHelper.saveSetting('sms_last_check', _lastCheckTime.toString());
    }

    // 리스너 등록 (절대 1회만)
    _registerSmsListener();

    _initialized = true;
    debugPrint('[SMS] 서비스 초기화 완료');
  }

  void _registerSmsListener() {
    if (_listenerRegistered) return;

    try {
      _telephony.listenIncomingSms(
        onNewMessage: _onSmsReceived,
        onBackgroundMessage: backgroundSmsHandler,
        listenInBackground: true,
      );
      _listenerRegistered = true;
      debugPrint('[SMS] 리스너 등록 완료');
    } catch (e) {
      debugPrint('[SMS] 백그라운드 리스너 실패: $e');
      try {
        _telephony.listenIncomingSms(
          onNewMessage: _onSmsReceived,
          listenInBackground: false,
        );
        _listenerRegistered = true;
      } catch (e2) {
        debugPrint('[SMS] 리스너 등록 완전 실패: $e2');
      }
    }
  }

  void _onSmsReceived(SmsMessage message) async {
    try {
      final body = message.body;
      if (body == null || body.isEmpty) return;
      debugPrint('[SMS-FG] 문자 수신: ${body.substring(0, body.length.clamp(0, 40))}...');

      final isEnabled = await _dbHelper.getSetting('sms_auto_register');
      if (isEnabled != 'true') return;

      final expense = await _processSmsBody(body);
      if (expense != null) {
        debugPrint('[SMS-FG] 자동 등록: ${expense.title} ${expense.amount}원');

        final popupEnabled = await _dbHelper.getSetting('popup_notification');
        if (popupEnabled == 'true') {
          try { await _showNotification(expense); } catch (_) {}
        }

        _expenseController.add(expense);
      }

      _updateLastCheckTime();
    } catch (e) {
      debugPrint('[SMS-FG] 처리 오류: $e');
    }
  }

  Future<void> _showNotification(Expense expense) async {
    final amountStr = '${expense.amount.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '지출 자동 등록',
      '${expense.title ?? '(매장명 없음)'} $amountStr',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'sms_expense',
          '문자 자동 등록',
          channelDescription: '카드 결제 문자를 자동으로 지출 등록합니다',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// 앱 복귀 시 새 문자 확인 (inbox 직접 조회, 리스너 무관)
  Future<List<Expense>> checkNewSms() async {
    final isEnabled = await _dbHelper.getSetting('sms_auto_register');
    if (isEnabled != 'true') return [];

    if (!_initialized) {
      final ok = await initializeIfPermitted();
      if (!ok) return [];
    }

    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE)
            .greaterThan(_lastCheckTime.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      debugPrint('[SMS] 새 문자 ${messages.length}건');

      final created = <Expense>[];
      for (final msg in messages) {
        final body = msg.body;
        if (body == null || body.isEmpty) continue;
        final expense = await _processSmsBody(body);
        if (expense != null) created.add(expense);
      }

      _updateLastCheckTime();
      return created;
    } catch (e) {
      debugPrint('[SMS] 새 문자 확인 실패: $e');
      return [];
    }
  }

  Future<Expense?> _processSmsBody(String body) async {
    final result = SmsParserService.parse(body);
    if (result == null) return null;

    final smsHash = body.hashCode.toRadixString(16);
    final alreadyProcessed = await _dbHelper.getSetting('sms_$smsHash');
    if (alreadyProcessed == 'true') return null;

    final trips = await _dbHelper.getAllTrips();
    final matchingTrip = _findMatchingTrip(trips, result.date);
    if (matchingTrip == null) {
      debugPrint('[SMS] 매칭 여행 없음: ${result.date}');
      return null;
    }

    final expense = Expense(
      tripId: matchingTrip.id!,
      amount: result.amount,
      category: '기타',
      paymentMethod: 'card',
      date: result.date,
      title: result.storeName,
      note: '[SMS 자동등록]',
    );

    final id = await _dbHelper.insertExpense(expense);
    await _dbHelper.saveSetting('sms_$smsHash', 'true');
    return expense.copyWith(id: id);
  }

  Trip? _findMatchingTrip(List<Trip> trips, DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    for (final trip in trips) {
      final start = DateTime(trip.startDate.year, trip.startDate.month, trip.startDate.day);
      final end = DateTime(trip.endDate.year, trip.endDate.month, trip.endDate.day);
      if (!dateOnly.isBefore(start) && !dateOnly.isAfter(end)) {
        return trip;
      }
    }
    return null;
  }

  void _updateLastCheckTime() {
    _lastCheckTime = DateTime.now().millisecondsSinceEpoch;
    _dbHelper.saveSetting('sms_last_check', _lastCheckTime.toString());
  }
}
