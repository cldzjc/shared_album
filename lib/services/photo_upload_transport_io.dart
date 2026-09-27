import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Android / iOS 上传实现：保持原有 http.put 直传逻辑，不引入任何新行为。
Future<void> putBytes({
  required String uploadUrl,
  required Uint8List bytes,
  required String contentType,
  void Function(double progress)? onProgress,
}) async {
  final uploadResponse = await http.put(
    Uri.parse(uploadUrl),
    headers: {'Content-Type': contentType},
    body: bytes,
  );

  if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
    throw Exception('OSS 上传失败: HTTP ${uploadResponse.statusCode}');
  }

  onProgress?.call(1.0);
}
