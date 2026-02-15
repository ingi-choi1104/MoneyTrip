import 'dart:convert';
import 'package:http/http.dart' as http;

class ExchangeRateService {
  static final ExchangeRateService instance = ExchangeRateService._init();
  ExchangeRateService._init();

  // 환율 캐시 (1시간마다 업데이트)
  Map<String, double>? _cachedRates;
  DateTime? _lastUpdate;

  // ExchangeRate-API (무료, API 키 불필요)
  final String _apiUrl = 'https://api.exchangerate-api.com/v4/latest/KRW';

  /// KRW 기준 환율 가져오기
  Future<Map<String, double>> getExchangeRates() async {
    // 캐시가 있고 1시간 이내면 캐시 사용
    if (_cachedRates != null && _lastUpdate != null) {
      final difference = DateTime.now().difference(_lastUpdate!);
      if (difference.inHours < 1) {
        print('환율 캐시 사용 (${difference.inMinutes}분 전 업데이트)');
        return _cachedRates!;
      }
    }

    try {
      print('환율 API 호출 중...');
      final response = await http.get(Uri.parse(_apiUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rates = data['rates'] as Map<String, dynamic>;

        // KRW를 기준으로 변환 (1 KRW -> 다른 통화)
        // 우리는 다른 통화 -> KRW로 바꿔야 하므로 역수 계산
        _cachedRates = {
          'KRW': 1.0,
          'USD': 1.0 / rates['USD'],
          'EUR': 1.0 / rates['EUR'],
          'JPY': 1.0 / rates['JPY'],
          'CNY': 1.0 / rates['CNY'],
          'GBP': 1.0 / rates['GBP'],
          'THB': 1.0 / rates['THB'],
          'VND': 1.0 / rates['VND'],
          'AUD': 1.0 / rates['AUD'],
          'CAD': 1.0 / rates['CAD'],
        };

        _lastUpdate = DateTime.now();
        print('환율 업데이트 성공!');
        print('USD: ${_cachedRates!['USD']!.toStringAsFixed(2)}원');
        print('EUR: ${_cachedRates!['EUR']!.toStringAsFixed(2)}원');

        return _cachedRates!;
      } else {
        print('환율 API 에러: ${response.statusCode}');
        return _getDefaultRates();
      }
    } catch (e) {
      print('환율 API 호출 실패: $e');
      // 네트워크 오류 시 기본값 사용
      return _getDefaultRates();
    }
  }

  /// 기본 환율 (API 실패 시 사용)
  Map<String, double> _getDefaultRates() {
    print('기본 환율 사용');
    return {
      'KRW': 1.0,
      'USD': 1380.0,
      'EUR': 1490.0,
      'JPY': 9.2,
      'CNY': 190.0,
      'GBP': 1750.0,
      'THB': 38.0,
      'VND': 0.056,
      'AUD': 890.0,
      'CAD': 990.0,
    };
  }

  /// 캐시 강제 새로고침
  void clearCache() {
    _cachedRates = null;
    _lastUpdate = null;
    print('환율 캐시 초기화');
  }

  /// 특정 금액을 KRW로 변환
  double convertToKRW(double amount, String fromCurrency) {
    final rates = _cachedRates ?? _getDefaultRates();
    return amount * (rates[fromCurrency] ?? 1.0);
  }

  /// 통화 간 변환 (from -> to)
  double convert(double amount, String from, String to) {
    if (from == to) return amount;
    final rates = _cachedRates ?? _getDefaultRates();
    // from -> KRW -> to
    final krwAmount = amount * (rates[from] ?? 1.0);
    final toRate = rates[to] ?? 1.0;
    if (toRate == 0) return amount;
    return krwAmount / toRate;
  }

  Map<String, double> get currentRates => _cachedRates ?? _getDefaultRates();
}
