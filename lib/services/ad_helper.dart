import 'dart:io';

class AdHelper {
  // 테스트 광고 단위 ID (출시 전 실제 ID로 교체)
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-6235846592723695/9682402831'; // Android 테스트 배너
    } else {
      return 'ca-app-pub-3940256099942544/2934735716'; // iOS 테스트 배너
    }
  }
}
