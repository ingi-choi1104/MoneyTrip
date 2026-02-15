import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'providers/expense_provider.dart';
import 'screens/trips_list_screen.dart';
import 'services/sms_service.dart';
import 'models/expense.dart';

/// 글로벌 네비게이터 키 — 어디서든 팝업/스낵바 표시 가능
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _provider = ExpenseProvider();
  StreamSubscription<Expense>? _smsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // SMS 실시간 수신 스트림 구독
    _smsSub = SmsService.instance.onExpenseCreated.listen(_onSmsExpenseCreated);
  }

  @override
  void dispose() {
    _smsSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      _provider.refreshData();

      // 초기화 완료 상태에서만 새 문자 확인 (inbox 직접 조회)
      if (SmsService.instance.isInitialized) {
        final created = await SmsService.instance.checkNewSms();
        if (created.isNotEmpty && _provider.isPopupNotification) {
          _showSmsPopup(created);
        }
      }
    }
  }

  /// 실시간 SMS 수신으로 지출 등록 시 호출
  void _onSmsExpenseCreated(Expense expense) {
    _provider.refreshData();
    if (_provider.isPopupNotification) {
      _showSmsPopup([expense]);
    }
  }

  /// SMS 자동등록 팝업 표시
  void _showSmsPopup(List<Expense> expenses) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    if (expenses.length == 1) {
      final e = expenses.first;
      final amountStr = _formatAmount(e.amount);

      showDialog(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.sms, color: const Color(0xFF6C63FF), size: 24),
              const SizedBox(width: 8),
              const Text('문자 자동 등록', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.title != null)
                Text('매장: ${e.title}', style: const TextStyle(fontSize: 16)),
              Text('금액: ${amountStr}원', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                '날짜: ${e.date.month}/${e.date.day} ${e.date.hour.toString().padLeft(2, '0')}:${e.date.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } else {
      // 여러 건 동시 등록
      showDialog(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.sms, color: const Color(0xFF6C63FF), size: 24),
              const SizedBox(width: 8),
              Text('문자 자동 등록 (${expenses.length}건)', style: const TextStyle(fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: expenses.length,
              itemBuilder: (_, i) {
                final e = expenses[i];
                final amountStr = _formatAmount(e.amount);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(e.title ?? '(매장명 없음)', overflow: TextOverflow.ellipsis)),
                      Text('${amountStr}원', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return _formatWithCommas(amount.toInt());
    }
    // 소수점이 있는 경우: 정수 부분에 쉼표 + 소수점 유지
    final parts = amount.toString().split('.');
    return '${_formatWithCommas(int.parse(parts[0]))}.${parts[1]}';
  }

  String _formatWithCommas(int value) {
    final str = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: '트립 머니',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.deepPurple,
          fontFamily: 'Pretendard',
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
          useMaterial3: true,
        ),
        home: const TripsListScreen(),
      ),
    );
  }
}
