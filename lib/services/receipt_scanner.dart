import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:math';
import 'ocr_space_service.dart';
import 'tab_scanner_service.dart';

class ReceiptScanResult {
  final double? amount;
  final String? storeName;
  final DateTime? date;
  final TimeOfDay? time;
  final String? address;

  ReceiptScanResult({
    this.amount,
    this.storeName,
    this.date,
    this.time,
    this.address,
  });
}

class ReceiptScanner {
  // ────────── 공용 진입점 ──────────
  // 이미지 압축 후 Tabscanner → OCR.space → ML Kit 순으로 시도
  static Future<ReceiptScanResult> scan(String imagePath) async {
    // 이미지를 1MB 이하로 압축
    final compressedPath = await _compressImage(imagePath);
    final pathToUse = compressedPath ?? imagePath;

    try {
      // 1순위: Tabscanner (구조화된 데이터 직접 추출)
      try {
        debugPrint('===== Tabscanner API 사용 =====');
        return await _scanWithTabscanner(pathToUse);
      } on TabScannerException catch (e) {
        debugPrint('Tabscanner 실패: $e');
      } catch (e) {
        debugPrint('Tabscanner 오류: $e');
      }

      // 2순위: OCR.space + 자체 파싱
      try {
        debugPrint('===== OCR.space API 사용 =====');
        return await _scanWithOcrSpace(pathToUse);
      } catch (e) {
        debugPrint('OCR.space 실패, ML Kit으로 폴백: $e');
      }

      // 3순위: ML Kit (오프라인)
      debugPrint('===== ML Kit 사용 =====');
      return await _scanWithMLKit(pathToUse);
    } finally {
      // 압축 임시 파일 정리
      if (compressedPath != null && compressedPath != imagePath) {
        try {
          await File(compressedPath).delete();
        } catch (_) {}
      }
    }
  }

  // ────────── 이미지 압축 (1MB 이하) ──────────
  static Future<String?> _compressImage(String imagePath) async {
    try {
      final file = File(imagePath);
      final fileSize = await file.length();
      const maxSize = 1024 * 1024; // 1MB

      if (fileSize <= maxSize) {
        debugPrint('이미지 크기 OK: ${(fileSize / 1024).toStringAsFixed(0)}KB');
        return null; // 압축 불필요
      }

      debugPrint('이미지 압축 필요: ${(fileSize / 1024).toStringAsFixed(0)}KB → 1024KB 이하로');

      final bytes = await file.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return null;

      // 해상도 축소: 비율 유지하면서 긴 변을 2000px 이하로
      var image = original;
      final maxDim = 2000;
      if (image.width > maxDim || image.height > maxDim) {
        if (image.width > image.height) {
          image = img.copyResize(image, width: maxDim);
        } else {
          image = img.copyResize(image, height: maxDim);
        }
        debugPrint('해상도 축소: ${original.width}x${original.height} → ${image.width}x${image.height}');
      }

      // JPEG 품질을 낮춰가며 1MB 이하 달성
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/receipt_compressed.jpg';

      for (var quality = 85; quality >= 30; quality -= 10) {
        final compressed = img.encodeJpg(image, quality: quality);
        if (compressed.length <= maxSize) {
          await File(tempPath).writeAsBytes(compressed);
          debugPrint('압축 완료: quality=$quality, ${(compressed.length / 1024).toStringAsFixed(0)}KB');
          return tempPath;
        }
      }

      // 최소 품질로도 초과 시 해상도를 더 줄임
      final smaller = img.copyResize(image,
          width: image.width > image.height ? 1200 : null,
          height: image.height >= image.width ? 1200 : null);
      final compressed = img.encodeJpg(smaller, quality: 50);
      await File(tempPath).writeAsBytes(compressed);
      debugPrint('강제 압축: ${(compressed.length / 1024).toStringAsFixed(0)}KB');
      return tempPath;
    } catch (e) {
      debugPrint('이미지 압축 실패: $e');
      return null; // 원본 사용
    }
  }

  // ────────── Tabscanner API 스캔 ──────────
  static Future<ReceiptScanResult> _scanWithTabscanner(String imagePath) async {
    final result = await TabScannerService.scanReceipt(imagePath);

    String? storeName = result.establishment;
    String? address = result.address;

    // 매장명이 '영수증'을 포함하면 자체 알고리즘으로 재추출
    if (storeName != null && storeName.contains('영수증')) {
      debugPrint('Tabscanner 매장명에 "영수증" 포함 → 자체 알고리즘 적용');
      storeName = null;
      // OCR.space로 텍스트 행을 얻어 자체 파싱
      try {
        final ocrResult = await OcrSpaceService.scanImage(imagePath);
        if (ocrResult.rows.isNotEmpty) {
          storeName = _extractStoreNameFromRows(ocrResult.rows);
        }
      } catch (e) {
        debugPrint('매장명 재추출용 OCR.space 실패: $e');
      }
    }

    // 주소가 없으면 자체 알고리즘으로 추출
    if (address == null || address.trim().isEmpty) {
      debugPrint('Tabscanner 주소 없음 → 자체 알고리즘 적용');
      try {
        final ocrResult = await OcrSpaceService.scanImage(imagePath);
        if (ocrResult.rows.isNotEmpty) {
          final isKorean = ocrResult.fullText.contains(RegExp(r'[ㄱ-ㅎ가-힣]'));
          address = _extractAddress(ocrResult.rows, isKorean);
        }
      } catch (e) {
        debugPrint('주소 재추출용 OCR.space 실패: $e');
      }
    }

    return ReceiptScanResult(
      amount: result.total,
      storeName: storeName,
      date: result.date,
      time: result.time,
      address: address,
    );
  }

  // ────────── OCR.space API 스캔 ──────────
  static Future<ReceiptScanResult> _scanWithOcrSpace(String imagePath) async {
    final ocrResult = await OcrSpaceService.scanImage(imagePath);
    final rows = ocrResult.rows;

    if (rows.isEmpty) {
      throw Exception('OCR.space: 텍스트를 인식하지 못했습니다');
    }

    final bool isKorean =
        ocrResult.fullText.contains(RegExp(r'[ㄱ-ㅎ가-힣]'));

    final amount = _extractAmount(rows, isKorean);
    final storeName = _extractStoreNameFromRows(rows);
    final (date, time) = _extractDateTime(rows);
    final address = _extractAddress(rows, isKorean);

    return ReceiptScanResult(
      amount: amount,
      storeName: storeName,
      date: date,
      time: time,
      address: address,
    );
  }

  // ────────── ML Kit 스캔 ──────────
  static Future<ReceiptScanResult> _scanWithMLKit(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer =
        TextRecognizer(script: TextRecognitionScript.korean);
    final RecognizedText recognized =
        await textRecognizer.processImage(inputImage);

    final List<TextLine> allLines = [];
    for (var block in recognized.blocks) {
      allLines.addAll(block.lines);
    }
    if (allLines.isEmpty) {
      await textRecognizer.close();
      return ReceiptScanResult();
    }
    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final rows = _groupIntoRows(allLines);

    debugPrint('===== 영수증 OCR 결과 =====');
    for (int i = 0; i < rows.length; i++) {
      debugPrint('[$i] ${rows[i]}');
    }

    final bool isKorean =
        recognized.text.contains(RegExp(r'[ㄱ-ㅎ가-힣]'));

    final amount = _extractAmount(rows, isKorean);
    final storeName = _extractStoreName(rows, allLines);
    final (date, time) = _extractDateTime(rows);
    final address = _extractAddress(rows, isKorean);

    await textRecognizer.close();
    return ReceiptScanResult(
      amount: amount,
      storeName: storeName,
      date: date,
      time: time,
      address: address,
    );
  }

  // ================================================================
  //  행 그룹핑 — 평균 라인 높이 기반 동적 임계값
  // ================================================================
  static List<String> _groupIntoRows(List<TextLine> lines) {
    double avgH = lines.fold<double>(
            0, (s, l) => s + l.boundingBox.height) /
        lines.length;
    double threshold = max(avgH * 0.6, 12);

    final List<String> result = [];
    List<TextLine> row = [lines[0]];

    for (int i = 1; i < lines.length; i++) {
      if ((lines[i].boundingBox.top - row.last.boundingBox.top).abs() <
          threshold) {
        row.add(lines[i]);
      } else {
        row.sort(
            (a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
        result.add(row.map((l) => l.text).join(' '));
        row = [lines[i]];
      }
    }
    row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    result.add(row.map((l) => l.text).join(' '));
    return result;
  }

  // ================================================================
  //  OCR 문자 보정
  // ================================================================
  static String _correctOcrChars(String s) {
    var r = s;
    r = r.replaceAll(RegExp(r'(?<=\d)[oOQD]'), '0');
    r = r.replaceAll(RegExp(r'[oO](?=\d)'), '0');
    r = r.replaceAll(RegExp(r'(?<=\d)[lIi|]'), '1');
    r = r.replaceAll(RegExp(r'[lI|](?=\d)'), '1');
    r = r.replaceAll(RegExp(r'(?<=\d)[S]'), '5');
    r = r.replaceAll(RegExp(r'(?<=\d)[B]'), '8');
    r = r.replaceAll(RegExp(r'(?<=\d)[Z]'), '2');
    r = r.replaceAll(RegExp(r'(?<=\d)[G]'), '6');
    r = r.replaceAll(RegExp(r'(?<=\d)[q]'), '9');
    r = r.replaceAll(RegExp(r'[₩\$€£¥\\]'), '');
    return r;
  }

  /// OCR에서 "8, 100" 처럼 쉼표/점 주변에 공백이 삽입되는 경우를 정규화.
  /// 숫자-공백-구분자-공백-숫자 → 숫자-구분자-숫자
  /// "1 7, 000" 같은 수량+금액 오합류를 방지하기 위해
  /// 전체 공백을 제거하지 않고 구분자 주변만 처리.
  static String _normalizeAmountSpaces(String s) {
    // "8, 100" → "8,100"  /  "7, 000" → "7,000"
    // 단, "1 7,000" 은 건드리지 않음
    return s.replaceAllMapped(
      RegExp(r'(\d)\s*([,.])\s*(\d)'),
      (m) => '${m.group(1)}${m.group(2)}${m.group(3)}',
    );
  }

  // ================================================================
  //  금액 추출
  // ================================================================

  // 한국 영수증에서 합계/결제 금액을 나타내는 키워드
  // OCR에서 글자 사이에 공백이 들어가므로 \s* 로 연결
  static final _totalKw = RegExp(
    r'합\s*계\s*(금\s*액)?'     // 합계, 합계금액
    r'|총\s*구\s*매\s*(액)?'    // 총구매액
    r'|총\s*액'                 // 총액
    r'|결\s*제\s*(금\s*액)?'    // 결제, 결제금액
    r'|승\s*인\s*(금\s*액)?'    // 승인, 승인금액
    r'|청\s*구\s*(금\s*액)?'    // 청구, 청구금액
    r'|받\s*[을은]\s*금\s*액'   // 받을금액, 받은금액
    r'|카\s*드\s*결\s*제'       // 카드결제
    r'|실\s*결\s*제'            // 실결제
    r'|총\s*결\s*제'            // 총결제
    r'|TOTAL|GRAND\s*TOTAL|AMOUNT\s*DUE|SUM'
    r'|PAGAR|SOMA|NET\s*AMOUNT|SUBTOTAL',
    caseSensitive: false,
  );

  // 합계가 아닌 부분 금액/메타 항목
  static final _noiseKw = RegExp(
    r'부\s*가\s*세'
    r'|세\s*액'
    r'|물\s*품\s*가\s*액'
    r'|과\s*세\s*물\s*품\s*가?\s*액?'
    r'|가\s*맹\s*점'
    r'|사\s*업\s*자'
    r'|면\s*세'
    r'|봉\s*사\s*료'
    r'|할\s*인'
    r'|포\s*인\s*트'
    r'|잔\s*액'
    r'|거\s*스\s*름'
    r'|수\s*량'
    r'|단\s*가'
    r'|TAX|VAT|IVA|TIP|DISC|CHANGE|BALANCE',
    caseSensitive: false,
  );

  // 쉼표/점 구분 금액 또는 순수 숫자(4자리 이상)
  static final _amountRe = RegExp(
    r'\d{1,3}(?:[,.]\d{3})+(?:[,.]\d{1,2})?'
    r'|\d{4,}(?:[,.]\d{1,2})?',
  );

  static double? _extractAmount(List<String> lines, bool isKorean) {
    List<(double value, int score)> candidates = [];

    for (int i = 0; i < lines.length; i++) {
      final original = lines[i];

      // ① OCR 문자 보정 → ② 쉼표/점 주변 공백만 정규화 (전체 공백 제거 X)
      final corrected = _normalizeAmountSpaces(_correctOcrChars(original));

      for (var m in _amountRe.allMatches(corrected)) {
        final raw = m.group(0)!;
        final val = _parseAmount(raw, isKorean);
        if (val == null || val < 100) continue;

        int score = 0;

        // 키워드 매칭은 원본 행에서 수행 (OCR 공백 그대로)
        final hasTotalKw = _totalKw.hasMatch(original);
        final hasNoiseKw = _noiseKw.hasMatch(original);

        // ① 같은 행에 합계 키워드
        if (hasTotalKw) {
          score += 50000;
        }
        // ② 앞 행이 합계 키워드
        else if (i > 0 && _totalKw.hasMatch(lines[i - 1])) {
          score += 35000;
        }
        // ③ 뒤 행이 합계 키워드
        else if (i + 1 < lines.length && _totalKw.hasMatch(lines[i + 1])) {
          score += 30000;
        }

        // ④ 노이즈 키워드가 있으면서 합계 키워드가 없으면 감점
        if (hasNoiseKw && !hasTotalKw) score -= 30000;

        // ⑤ 하단 위치 가점
        score += (i * 1000 ~/ max(lines.length, 1));

        // ⑥ 큰 금액 가점 (합계 > 개별 항목)
        score += min(val ~/ 100, 5000);

        candidates.add((val, score));
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    return candidates.first.$1;
  }

  static double? _parseAmount(String text, bool isKorean) {
    if (isKorean) {
      return double.tryParse(text.replaceAll(RegExp(r'[,.]'), ''));
    }
    final lastSep = text.lastIndexOf(RegExp(r'[,.]'));
    if (lastSep == -1) return double.tryParse(text);
    final suffix = text.substring(lastSep + 1);
    if (suffix.length <= 2) {
      final prefix =
          text.substring(0, lastSep).replaceAll(RegExp(r'[,.]'), '');
      return double.tryParse('$prefix.$suffix');
    }
    return double.tryParse(text.replaceAll(RegExp(r'[,.]'), ''));
  }

  // ================================================================
  //  상호명 추출 (다중 전략)
  // ================================================================

  // [매장명], [상호명], 매장명:, 상호: 등 대괄호/콜론 포함
  static final _storeKeyRe = RegExp(
    r'[\[<]?\s*(매\s*장\s*명|상\s*호\s*(명)?|STORE|SHOP|MERCHANT)\s*[\]>]?\s*[:\-]?\s*(.*)',
    caseSensitive: false,
  );
  static final _skipStoreRe = RegExp(
    r'(영수증|발행|인쇄|RECEIPT|합계|결제|승인|사업자|대표자|전화|TEL|FAX|'
    r'카드|거래|일시|주소|번호|www\.|\.com|\.kr|http|부가세|세금|'
    r'면세|과세|NO\.|#\d|\d{3}[\-]\d{3,}|매출일|주문번호)',
    caseSensitive: false,
  );

  static String? _extractStoreName(
      List<String> rows, List<TextLine> allLines) {
    // 전략 1: "매장명", "상호" 등 명시적 키워드
    for (var row in rows.take(15)) {
      final m = _storeKeyRe.firstMatch(row);
      if (m != null) {
        final raw = m.group(3)?.trim() ?? '';
        // "/" 앞 부분만 (사업자번호 분리)
        final name = raw.split('/').first.trim();
        if (name.isNotEmpty && name.length >= 2) return name;
      }
    }

    // 전략 2: 영수증 상단의 가장 큰(굵은) 텍스트 = 상호명 추정
    if (allLines.isNotEmpty) {
      final totalHeight = allLines.last.boundingBox.bottom -
          allLines.first.boundingBox.top;
      final topCutoff =
          allLines.first.boundingBox.top + totalHeight * 0.4;

      TextLine? best;
      double bestHeight = 0;
      for (var line in allLines) {
        if (line.boundingBox.top > topCutoff) break;
        final text = line.text.trim();
        if (text.length < 2 || text.length > 30) continue;
        if (_skipStoreRe.hasMatch(text)) continue;
        if (RegExp(r'^\d+$').hasMatch(text.replaceAll(RegExp(r'[\s\-]'), ''))) {
          continue;
        }
        if (line.boundingBox.height > bestHeight) {
          bestHeight = line.boundingBox.height;
          best = line;
        }
      }
      if (best != null) {
        final name = best.text.trim();
        if (name.isNotEmpty) return name;
      }
    }

    // 전략 3: 상단 5행 중 한글/영문 2글자 이상이면서 노이즈 아닌 첫 행
    for (var row in rows.take(5)) {
      final cleaned = row.trim();
      if (cleaned.length < 2 || cleaned.length > 30) continue;
      if (_skipStoreRe.hasMatch(cleaned)) continue;
      if (RegExp(r'^\d+[\s\-./\d]*$').hasMatch(cleaned)) continue;
      if (RegExp(r'[ㄱ-ㅎ가-힣a-zA-Z]').hasMatch(cleaned)) {
        return cleaned;
      }
    }

    return null;
  }

  /// OCR.space용: TextLine 좌표 없이 행 텍스트만으로 상호명 추출
  static String? _extractStoreNameFromRows(List<String> rows) {
    // 전략 1: 명시적 키워드
    for (var row in rows.take(15)) {
      final m = _storeKeyRe.firstMatch(row);
      if (m != null) {
        final raw = m.group(3)?.trim() ?? '';
        final name = raw.split('/').first.trim();
        if (name.isNotEmpty && name.length >= 2) return name;
      }
    }

    // 전략 2: 상단 5행 중 노이즈 아닌 첫 행
    for (var row in rows.take(5)) {
      final cleaned = row.trim();
      if (cleaned.length < 2 || cleaned.length > 30) continue;
      if (_skipStoreRe.hasMatch(cleaned)) continue;
      if (RegExp(r'^\d+[\s\-./\d]*$').hasMatch(cleaned)) continue;
      if (RegExp(r'[ㄱ-ㅎ가-힣a-zA-Z]').hasMatch(cleaned)) {
        return cleaned;
      }
    }

    return null;
  }

  // ================================================================
  //  날짜 & 시간 추출 (다중 포맷)
  // ================================================================

  // 날짜 키워드가 있는 행을 우선 탐색
  static final _dateHintKw = RegExp(
    r'(매\s*출\s*일|승\s*인\s*일\s*시|거\s*래\s*일\s*시|일\s*시|날\s*짜|DATE)',
    caseSensitive: false,
  );

  static (DateTime?, TimeOfDay?) _extractDateTime(List<String> lines) {
    DateTime? date;
    TimeOfDay? time;

    final datePatterns = [
      RegExp(r'(20\d{2})[./\-](\d{1,2})[./\-](\d{1,2})'),
      RegExp(r'(\d{1,2})[./\-](\d{1,2})[./\-](20\d{2})'),
      RegExp(r'(20\d{2})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일'),
      RegExp(r'(\d{2})[./\-](\d{2})[./\-](\d{2})'),
      RegExp(r'(?<!\d)(20\d{6})(?!\d)'),
    ];

    final timePatterns = [
      RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?'),
      RegExp(r'(\d{1,2})시\s*(\d{1,2})분'),
    ];

    // 날짜 키워드가 포함된 행을 맨 앞에 배치하여 우선 탐색
    final sortedLines = List<String>.from(lines);
    sortedLines.sort((a, b) {
      final aHas = _dateHintKw.hasMatch(a) ? 0 : 1;
      final bHas = _dateHintKw.hasMatch(b) ? 0 : 1;
      return aHas.compareTo(bHas);
    });

    for (var line in sortedLines) {
      if (date == null) {
        date = _tryParseDate(line, datePatterns);
      }
      if (time == null) {
        time = _tryParseTime(line, timePatterns);
      }
      if (date != null && time != null) break;
    }

    // 시간을 못 찾았으면 원본 순서로 재탐색 (날짜 행 다음 행 등)
    if (time == null) {
      for (var line in lines) {
        time = _tryParseTime(line, timePatterns);
        if (time != null) break;
      }
    }

    return (date, time);
  }

  static DateTime? _tryParseDate(String line, List<RegExp> patterns) {
    for (int pi = 0; pi < patterns.length; pi++) {
      final m = patterns[pi].firstMatch(line);
      if (m == null) continue;

      try {
        DateTime? parsed;
        if (pi == 0) {
          parsed = DateTime(
            int.parse(m.group(1)!),
            int.parse(m.group(2)!),
            int.parse(m.group(3)!),
          );
        } else if (pi == 1) {
          parsed = DateTime(
            int.parse(m.group(3)!),
            int.parse(m.group(2)!),
            int.parse(m.group(1)!),
          );
        } else if (pi == 2) {
          parsed = DateTime(
            int.parse(m.group(1)!),
            int.parse(m.group(2)!),
            int.parse(m.group(3)!),
          );
        } else if (pi == 3) {
          int v1 = int.parse(m.group(1)!);
          int v2 = int.parse(m.group(2)!);
          int v3 = int.parse(m.group(3)!);
          if (v1 >= 20 && v1 <= 35 && v2 <= 12 && v3 <= 31) {
            parsed = DateTime(2000 + v1, v2, v3);
          } else if (v3 >= 20 && v3 <= 35 && v2 <= 12 && v1 <= 31) {
            parsed = DateTime(2000 + v3, v2, v1);
          }
        } else if (pi == 4) {
          final s = m.group(1)!;
          parsed = DateTime(
            int.parse(s.substring(0, 4)),
            int.parse(s.substring(4, 6)),
            int.parse(s.substring(6, 8)),
          );
        }

        if (parsed != null &&
            parsed.year >= 2020 &&
            parsed.year <= 2030 &&
            parsed.month >= 1 &&
            parsed.month <= 12 &&
            parsed.day >= 1 &&
            parsed.day <= 31) {
          return parsed;
        }
      } catch (_) {}
    }
    return null;
  }

  static TimeOfDay? _tryParseTime(String line, List<RegExp> patterns) {
    for (var pat in patterns) {
      final tm = pat.firstMatch(line);
      if (tm == null) continue;
      final h = int.parse(tm.group(1)!);
      final m = int.parse(tm.group(2)!);
      if (h >= 0 && h < 24 && m >= 0 && m < 60) {
        return TimeOfDay(hour: h, minute: m);
      }
    }
    return null;
  }

  // ================================================================
  //  주소 추출
  // ================================================================
  static final _addrKeyRe = RegExp(
    r'[\[<]?\s*(주\s*소|addr)\s*[\]>]?',
    caseSensitive: false,
  );
  static final _krAddrRe = RegExp(
    r'[\uAC00-\uD7A3]+(?:특별시|광역시|특별자치시|특별자치도|도|시|군|구)'
    r'[\s\uAC00-\uD7A3]*(?:읍|면|동|리|로|길|가)'
    r'[\s\d\-\uAC00-\uD7A3]*',
  );
  static final _krAddrSimpleRe = RegExp(
    r'[\uAC00-\uD7A3]{2,}(?:로|길)\s*\d+',
  );

  static String? _extractAddress(List<String> lines, bool isKorean) {
    if (!isKorean) return null;

    // 전략 1: "주소" 키워드가 있는 행 + 다음 행까지 연결
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_addrKeyRe.hasMatch(line)) {
        var cleaned = line
            .replaceAll(
                RegExp(r'^.*?[\[<]?\s*(주\s*소|addr)\s*[\]>]?\s*[:\-：]?\s*',
                    caseSensitive: false),
                '')
            .trim();
        // 다음 행이 주소 연속인 경우 병합 (예: 호계동, 한솔센트럴마크)
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          // 다음 행이 한글로 시작하고 키워드가 아닌 경우
          if (nextLine.isNotEmpty &&
              RegExp(r'^[\uAC00-\uD7A3(]').hasMatch(nextLine) &&
              !RegExp(r'(대표|TEL|전화|매출|사업)').hasMatch(nextLine)) {
            cleaned = '$cleaned $nextLine';
          }
        }
        // 끝의 닫는 괄호/불필요 문자 정리
        cleaned = cleaned.replaceAll(RegExp(r'\s*\)\s*$'), ')').trim();
        if (cleaned.length >= 5 &&
            RegExp(r'[\uAC00-\uD7A3]').hasMatch(cleaned)) {
          return cleaned;
        }
      }
    }

    // 전략 2: 행정구역 패턴
    for (var line in lines) {
      final m = _krAddrRe.firstMatch(line);
      if (m != null && m.group(0)!.length >= 6) {
        return m.group(0)!.trim();
      }
    }

    // 전략 3: 간단 도로명
    for (var line in lines) {
      final m = _krAddrSimpleRe.firstMatch(line);
      if (m != null) return m.group(0)!.trim();
    }

    return null;
  }
}
