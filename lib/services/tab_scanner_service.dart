import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class TabScannerService {
  static const String _apiKey = 'wXXuC8VfPassY015IUgnq0V2RGsehbbvUEzjDsOXpn2Ho2Ko4IDJg1yAQlIhDJQ2';
  static const String _baseUrl = 'https://api.tabscanner.com';

  /// 영수증 이미지를 Tabscanner API로 전송하여 구조화된 데이터 추출
  static Future<TabScannerResult> scanReceipt(String imagePath) async {
    // 1단계: 이미지 업로드 → 토큰 수신
    final token = await _uploadImage(imagePath);

    // 2단계: 결과 폴링 (최대 15초)
    final result = await _pollResult(token);

    return result;
  }

  /// 남은 크레딧 조회
  static Future<int> getRemainingCredits() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/credit'),
        headers: {'apikey': _apiKey},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data is int) ? data : (data as num).toInt();
      }
      return -1;
    } catch (e) {
      debugPrint('크레딧 조회 실패: $e');
      return -1;
    }
  }

  static Future<String> _uploadImage(String imagePath) async {
    final file = File(imagePath);
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/2/process'),
    );

    request.headers['apikey'] = _apiKey;
    request.fields['documentType'] = 'receipt';
    request.fields['region'] = 'kr';
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path),
    );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 30),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200 && response.statusCode != 300) {
      final data = json.decode(response.body);
      final code = data['code'] ?? response.statusCode;
      if (code == 401) {
        throw TabScannerException('크레딧 부족', isQuotaExceeded: true);
      }
      throw TabScannerException('업로드 실패 (코드: $code)');
    }

    final data = json.decode(response.body);
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw TabScannerException('토큰을 받지 못했습니다');
    }

    debugPrint('Tabscanner 토큰: $token');
    return token;
  }

  static Future<TabScannerResult> _pollResult(String token) async {
    // 초기 5초 대기 후 1초 간격으로 폴링 (최대 15초)
    await Future.delayed(const Duration(seconds: 5));

    for (int attempt = 0; attempt < 10; attempt++) {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/result/$token'),
        headers: {'apikey': _apiKey},
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      final status = data['status'] as String?;

      if (status == 'done') {
        final result = data['result'] as Map<String, dynamic>?;
        if (result == null) {
          throw TabScannerException('결과 데이터가 없습니다');
        }
        return _parseResult(result);
      } else if (status == 'failed') {
        throw TabScannerException('영수증 처리 실패');
      }

      // pending → 1초 후 재시도
      await Future.delayed(const Duration(seconds: 1));
    }

    throw TabScannerException('처리 시간 초과');
  }

  static TabScannerResult _parseResult(Map<String, dynamic> result) {
    debugPrint('===== Tabscanner 결과 =====');
    debugPrint('매장명: ${result['establishment']}');
    debugPrint('총액: ${result['total']}');
    debugPrint('날짜: ${result['date']}');
    debugPrint('주소: ${result['address']}');

    // 금액
    final total = (result['total'] as num?)?.toDouble();

    // 매장명
    final establishment = result['establishment'] as String?;

    // 날짜/시간 파싱: "YYYY-MM-DD hh:mm:ss" 형식
    DateTime? date;
    TimeOfDay? time;
    final dateStr = result['date'] as String?;
    if (dateStr != null && dateStr.isNotEmpty) {
      final parsed = _parseDateTimeString(dateStr);
      date = parsed.$1;
      time = parsed.$2;
    }

    // 주소
    final address = result['address'] as String?;

    // 품목 목록
    final lineItems = <TabScannerLineItem>[];
    final items = result['lineItems'] as List?;
    if (items != null) {
      for (var item in items) {
        final map = item as Map<String, dynamic>;
        lineItems.add(TabScannerLineItem(
          description: map['desc'] as String? ?? '',
          descriptionClean: map['descClean'] as String? ?? '',
          quantity: (map['qty'] as num?)?.toDouble(),
          price: (map['price'] as num?)?.toDouble(),
          lineTotal: (map['lineTotal'] as num?)?.toDouble(),
        ));
      }
    }

    debugPrint('품목 수: ${lineItems.length}');
    for (var item in lineItems) {
      debugPrint('  - ${item.description}: ${item.lineTotal}');
    }

    return TabScannerResult(
      total: total,
      establishment: establishment,
      date: date,
      time: time,
      address: address,
      lineItems: lineItems,
    );
  }

  static (DateTime?, TimeOfDay?) _parseDateTimeString(String dateStr) {
    DateTime? date;
    TimeOfDay? time;

    try {
      // "YYYY-MM-DD hh:mm:ss" 또는 "YYYY-MM-DD"
      final parts = dateStr.split(' ');
      if (parts.isNotEmpty) {
        final dateParts = parts[0].split('-');
        if (dateParts.length == 3) {
          date = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          );
        }
      }
      if (parts.length >= 2) {
        final timeParts = parts[1].split(':');
        if (timeParts.length >= 2) {
          final h = int.parse(timeParts[0]);
          final m = int.parse(timeParts[1]);
          if (h >= 0 && h < 24 && m >= 0 && m < 60) {
            time = TimeOfDay(hour: h, minute: m);
          }
        }
      }
    } catch (e) {
      debugPrint('날짜 파싱 실패: $dateStr → $e');
    }

    return (date, time);
  }
}

class TabScannerResult {
  final double? total;
  final String? establishment;
  final DateTime? date;
  final TimeOfDay? time;
  final String? address;
  final List<TabScannerLineItem> lineItems;

  TabScannerResult({
    this.total,
    this.establishment,
    this.date,
    this.time,
    this.address,
    this.lineItems = const [],
  });
}

class TabScannerLineItem {
  final String description;
  final String descriptionClean;
  final double? quantity;
  final double? price;
  final double? lineTotal;

  TabScannerLineItem({
    required this.description,
    required this.descriptionClean,
    this.quantity,
    this.price,
    this.lineTotal,
  });
}

class TabScannerException implements Exception {
  final String message;
  final bool isQuotaExceeded;

  TabScannerException(this.message, {this.isQuotaExceeded = false});

  @override
  String toString() => 'TabScannerException: $message';
}
