import 'package:flutter/foundation.dart';

/// 한국 카드 결제 문자(SMS)에서 금액, 매장명, 날짜를 추출하는 파서
///
/// 지원 포맷 예시:
///   [KB국민] 홍*동 02/15 12:30 15,000원 스타벅스 일시불 승인
///   [신한카드] 홍길동님 승인 12,000원 맥도날드 02/15 14:20
///   [삼성] 홍*동 50,000원 결제 이마트 02.15
///   [현대카드] 홍길동님 02/15 08:30 결제 8,500원 GS25
///   [하나] 체크승인 홍*동 15,000원 02/15 09:00 편의점
///   [우리] 홍길동님 체크 23,000원 결제 올리브영 02/15
///   [롯데] 홍*동 승인 32,000원 02/15 16:30 무신사
///   [NH] 홍*동님 02/15 11:20 승인 7,000원 서브웨이
class SmsParserService {
  /// 결제 문자를 파싱하여 결과 반환. 결제 문자가 아니면 null.
  static SmsParseResult? parse(String body) {
    debugPrint('[SMS 파서] 입력: $body');

    if (!_isPaymentSms(body)) {
      debugPrint('[SMS 파서] 결제 문자 아님 → skip');
      return null;
    }

    final amount = _extractAmount(body);
    if (amount == null) {
      debugPrint('[SMS 파서] 금액 추출 실패 → skip');
      return null;
    }

    final storeName = _extractStoreName(body);
    final date = _extractDate(body);

    debugPrint('[SMS 파서] 파싱 결과: 금액=$amount, 매장=$storeName, 날짜=$date');

    return SmsParseResult(
      amount: amount,
      storeName: storeName,
      date: date ?? DateTime.now(),
    );
  }

  // ─── 결제 문자 판별 ───

  static bool _isPaymentSms(String body) {
    // 결제/승인 키워드 + 금액(원) 필수
    final hasPaymentKw = RegExp(
      r'(결제|승인|출금|이용금액|사용)',
    ).hasMatch(body);
    final hasAmount = RegExp(r'[\d,]+\s*원').hasMatch(body);

    // 취소/거절 문자 제외
    final isCancelled = RegExp(r'(취소|거절|실패|반려|철회)').hasMatch(body);

    return hasPaymentKw && hasAmount && !isCancelled;
  }

  // ─── 금액 추출 ───

  static double? _extractAmount(String body) {
    final text = body.replaceAll('\n', ' ').replaceAll('\r', '');

    // 전략 1: 결제/승인/사용 키워드 근처의 금액 (잔액/누적 키워드 근처 금액 제외)
    // "승인 15,000원", "결제 8,500원", "사용금액 12,000원"
    for (final p in [
      RegExp(r'(?:결제|승인|사용금액|이용금액|사용|출금)\s*([\d,]+)\s*원'),
      RegExp(r'([\d,]+)\s*원\s*(?:결제|승인|사용|일시불|할부)'),
    ]) {
      final m = p.firstMatch(text);
      if (m != null) {
        final raw = m.group(1)!.replaceAll(',', '');
        final val = double.tryParse(raw);
        if (val != null && val > 0) {
          debugPrint('[SMS 파서] 결제 키워드 근처 금액: $val');
          return val;
        }
      }
    }

    // 전략 2: 잔액/누적/한도 키워드가 붙지 않은 첫 번째 금액
    final allMatches = RegExp(r'([\d,]+)\s*원').allMatches(text).toList();
    for (final m in allMatches) {
      // 이 금액 앞에 잔액/누적/한도 키워드가 있는지 확인
      final before = text.substring(0, m.start);
      if (RegExp(r'(?:잔액|누적|한도|잔여)\s*$').hasMatch(before)) {
        debugPrint('[SMS 파서] 잔액 관련 금액 skip: ${m.group(1)}');
        continue;
      }
      final raw = m.group(1)!.replaceAll(',', '');
      final val = double.tryParse(raw);
      if (val != null && val > 0) {
        debugPrint('[SMS 파서] 첫 번째 유효 금액: $val');
        return val;
      }
    }

    return null;
  }

  // ─── 매장명 추출 ───

  /// 날짜(+시간) 바로 뒤에 오는 텍스트를 매장명으로 추출
  static String? _extractStoreName(String body) {
    final text = body.replaceAll('\n', ' ').replaceAll('\r', '');

    // ★ 핵심 전략: 날짜(+시간) 바로 다음에 오는 텍스트 = 매장명
    //   "02/15 12:30 스타벅스 15,000원"
    //   "02/15 12:30 스타벅스코리아 15,000원 일시불 승인"
    //   "02.15 09:00 GS25편의점 7,000원"
    {
      final m = RegExp(
        r'\d{1,2}[/.]\d{1,2}\s+\d{1,2}:\d{2}\s+(.+?)(?:\s+[\d,]+\s*원|$)',
      ).firstMatch(text);
      if (m != null) {
        final name = _cleanStoreName(m.group(1)!);
        if (name != null) {
          debugPrint('[SMS 파서] 날짜+시간 뒤 매장명: $name');
          return name;
        }
      }
    }

    // 날짜(시간 없이) 바로 다음 텍스트
    //   "02/15 스타벅스 15,000원"
    {
      final m = RegExp(
        r'\d{1,2}[/.]\d{1,2}\s+(.+?)(?:\s+[\d,]+\s*원|$)',
      ).firstMatch(text);
      if (m != null) {
        // 시간 패턴으로 시작하면 건너뜀 (날짜+시간 케이스가 이미 처리됨)
        final candidate = m.group(1)!.trim();
        if (!RegExp(r'^\d{1,2}:\d{2}').hasMatch(candidate)) {
          final name = _cleanStoreName(candidate);
          if (name != null) {
            debugPrint('[SMS 파서] 날짜 뒤 매장명: $name');
            return name;
          }
        }
      }
    }

    // 보조 전략: 금액(원) 뒤 키워드 뒤 텍스트
    //   "15,000원 일시불 승인 스타벅스"
    {
      final m = RegExp(
        r'원\s+(?:일시불|할부|\d+개월)?\s*(?:결제|승인)\s+(.+?)(?:\s+\d{1,2}[/.]\d{1,2}|$)',
      ).firstMatch(text);
      if (m != null) {
        final name = _cleanStoreName(m.group(1)!);
        if (name != null) {
          debugPrint('[SMS 파서] 금액 뒤 키워드 뒤 매장명: $name');
          return name;
        }
      }
    }

    // 최후 전략: 모든 날짜/금액/키워드를 제거하고 남은 토큰
    {
      var cleaned = text;
      cleaned = cleaned.replaceAll(RegExp(r'\[.+?\]'), '');
      cleaned = cleaned.replaceAll(RegExp(r'\d{1,2}[/.]\d{1,2}(\s+\d{1,2}:\d{2})?'), '');
      cleaned = cleaned.replaceAll(RegExp(r'[\d,]+\s*원'), '');
      cleaned = cleaned.replaceAll(
        RegExp(r'(승인|결제|일시불|할부|체크|출금|사용|이용금액|님|씨|\d+개월|누적|잔액|한도|국내|해외|\*+)'),
        '',
      );
      cleaned = cleaned.replaceAll(RegExp(r'[가-힣]\*[가-힣]'), '');
      // 이름 패턴 제거 (홍길동, 홍*동 등)
      cleaned = cleaned.replaceAll(RegExp(r'홍\S*'), '');

      final tokens = cleaned.split(RegExp(r'\s+')).where((t) {
        t = t.trim();
        return t.length >= 2 && RegExp(r'[가-힣a-zA-Z]').hasMatch(t);
      }).toList();

      if (tokens.isNotEmpty) {
        debugPrint('[SMS 파서] 잔여 토큰 매장명: ${tokens.first.trim()}');
        return tokens.first.trim();
      }
    }

    return null;
  }

  /// 매장명 정리: 불필요한 문자 제거, 유효성 검사
  static String? _cleanStoreName(String raw) {
    var name = raw.trim();
    // 시간 패턴 제거 (앞에 남아있을 수 있음)
    name = name.replaceAll(RegExp(r'^\d{1,2}:\d{2}\s*'), '').trim();
    // 날짜/시간 제거
    name = name.replaceAll(RegExp(r'\d{1,2}[/.]\d{1,2}(\s+\d{1,2}:\d{2})?'), '').trim();
    // 누적/잔액 등 뒤의 모든 텍스트 제거
    name = name.replaceAll(RegExp(r'\s*(누적|잔액|한도|국내|해외).*'), '').trim();
    // 금액 패턴 제거
    name = name.replaceAll(RegExp(r'[\d,]+\s*원'), '').trim();
    // 승인/결제 키워드 제거
    name = name.replaceAll(RegExp(r'(승인|결제|일시불|할부|체크|출금|사용)'), '').trim();

    if (name.length >= 2 && RegExp(r'[가-힣a-zA-Z]').hasMatch(name)) {
      return name;
    }
    return null;
  }

  // ─── 날짜 추출 ───

  static DateTime? _extractDate(String body) {
    // 패턴 1: "MM/DD HH:MM" 또는 "MM.DD HH:MM"
    final withTime = RegExp(r'(\d{1,2})[/.](\d{1,2})\s+(\d{1,2}):(\d{2})').firstMatch(body);
    if (withTime != null) {
      final month = int.parse(withTime.group(1)!);
      final day = int.parse(withTime.group(2)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return _buildDateTime(
          month, day,
          int.parse(withTime.group(3)!),
          int.parse(withTime.group(4)!),
        );
      }
    }

    // 패턴 2: "MM/DD" (시간 없음)
    final dateOnly = RegExp(r'(\d{1,2})[/.](\d{1,2})').firstMatch(body);
    if (dateOnly != null) {
      final month = int.parse(dateOnly.group(1)!);
      final day = int.parse(dateOnly.group(2)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return _buildDateTime(month, day, null, null);
      }
    }

    return null;
  }

  static DateTime _buildDateTime(int month, int day, int? hour, int? minute) {
    final now = DateTime.now();
    int year = now.year;
    if (month > now.month || (month == now.month && day > now.day)) {
      year -= 1;
    }
    return DateTime(year, month, day, hour ?? 0, minute ?? 0);
  }
}

class SmsParseResult {
  final double amount;
  final String? storeName;
  final DateTime date;

  SmsParseResult({
    required this.amount,
    this.storeName,
    required this.date,
  });
}
