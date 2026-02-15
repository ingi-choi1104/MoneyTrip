import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OcrSpaceService {
  static const String _apiKey = 'K89743254188957';
  static const String _apiUrl = 'https://api.ocr.space/parse/image';

  /// 이미지 파일을 OCR.space API로 전송하여 텍스트 추출
  static Future<OcrSpaceResult> scanImage(String imagePath) async {

    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);

    // 파일 확장자로 MIME 타입 결정
    final ext = imagePath.toLowerCase().split('.').last;
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'apikey': _apiKey},
        body: {
          'base64Image': 'data:$mimeType;base64,$base64Image',
          'language': 'kor',
          'isOverlayRequired': 'true',
          'scale': 'true',
          'isTable': 'true',
          'OCREngine': '2',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('API 응답 오류: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['IsErroredOnProcessing'] == true) {
        throw Exception(data['ErrorMessage'] ?? 'OCR 처리 오류');
      }

      final parsedResults = data['ParsedResults'] as List?;
      if (parsedResults == null || parsedResults.isEmpty) {
        throw Exception('OCR 결과가 없습니다');
      }

      final result = parsedResults[0];
      final exitCode = result['FileParseExitCode'];
      if (exitCode != 1) {
        throw Exception(result['ErrorMessage'] ?? 'OCR 파싱 실패 (코드: $exitCode)');
      }

      // Overlay에서 행별 텍스트 + 좌표 추출
      final rows = _extractRowsFromOverlay(result);
      final fullText = result['ParsedText'] as String? ?? '';

      debugPrint('===== OCR.space API 결과 =====');
      for (int i = 0; i < rows.length; i++) {
        debugPrint('[$i] ${rows[i]}');
      }

      return OcrSpaceResult(rows: rows, fullText: fullText);
    } on SocketException {
      throw Exception('네트워크 연결 실패');
    } on HttpException {
      throw Exception('HTTP 요청 실패');
    }
  }

  /// TextOverlay의 Lines에서 행별 텍스트를 추출
  /// 각 Line의 Words를 Left 좌표순으로 정렬 후 합침
  /// Lines는 MinTop 기준으로 세로 정렬
  static List<String> _extractRowsFromOverlay(Map<String, dynamic> result) {
    final overlay = result['TextOverlay'] as Map<String, dynamic>?;
    if (overlay == null || overlay['HasOverlay'] != true) {
      // Overlay 없으면 ParsedText를 줄 단위로 분리
      final text = result['ParsedText'] as String? ?? '';
      return text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    final lines = overlay['Lines'] as List? ?? [];
    if (lines.isEmpty) {
      final text = result['ParsedText'] as String? ?? '';
      return text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    // MinTop 기준으로 세로 정렬
    final sortedLines = List<Map<String, dynamic>>.from(
      lines.map((l) => l as Map<String, dynamic>),
    );
    sortedLines.sort((a, b) {
      final aTop = (a['MinTop'] as num?)?.toDouble() ?? 0;
      final bTop = (b['MinTop'] as num?)?.toDouble() ?? 0;
      return aTop.compareTo(bTop);
    });

    final List<String> rows = [];
    for (var line in sortedLines) {
      final words = line['Words'] as List? ?? [];
      if (words.isEmpty) continue;

      // Words를 Left 좌표순 정렬 후 합침
      final sortedWords = List<Map<String, dynamic>>.from(
        words.map((w) => w as Map<String, dynamic>),
      );
      sortedWords.sort((a, b) {
        final aLeft = (a['Left'] as num?)?.toDouble() ?? 0;
        final bLeft = (b['Left'] as num?)?.toDouble() ?? 0;
        return aLeft.compareTo(bLeft);
      });

      final text = sortedWords
          .map((w) => w['WordText'] as String? ?? '')
          .join(' ')
          .trim();
      if (text.isNotEmpty) rows.add(text);
    }

    return rows;
  }
}

class OcrSpaceResult {
  final List<String> rows;
  final String fullText;

  OcrSpaceResult({required this.rows, required this.fullText});
}
