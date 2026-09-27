import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 统一图片 URL 服务
///
/// 所有 OSS 图片 URL 变换集中在这里，不散落在各页面。
/// 未来换 OSS / 七牛 / R2 / Supabase Storage 时只改这个文件。
class PhotoImageService {
  /// 缩略图：网格列表、相册封面 → OSS 样式 small-photos
  static String getThumbnail(String fileUrl) {
    return _appendStyle(fileUrl, 'small-photos');
  }

  /// 预览图：全屏浏览 → OSS 样式 preview
  static String getPreview(String fileUrl) {
    return _appendStyle(fileUrl, 'preview');
  }

  /// 原图：下载、保存到系统相册
  static String getOriginal(String fileUrl) {
    return fileUrl;
  }

  static String _appendStyle(String fileUrl, String style) {
    if (fileUrl.contains('?')) {
      return '$fileUrl&x-oss-process=style/$style';
    }
    return '$fileUrl?x-oss-process=style/$style';
  }

  /// Debug：实际下载并统计 Thumbnail / Preview / Original 的真实字节大小与耗时
  static Future<void> debugImageInfo(String fileUrl) async {
    if (!kDebugMode) return;

    final entries = <String, String>{
      'Thumbnail': getThumbnail(fileUrl),
      'Preview': getPreview(fileUrl),
      'Original': getOriginal(fileUrl),
    };

    debugPrint('══════════ [PhotoImage DEBUG] ══════════');
    for (final entry in entries.entries) {
      try {
        final stopwatch = Stopwatch()..start();
        final response = await http.get(Uri.parse(entry.value));
        stopwatch.stop();
        final sizeStr = _formatBytes(response.bodyBytes.length);
        debugPrint(
          '  ${entry.key} | ${response.statusCode} | $sizeStr | ${stopwatch.elapsedMilliseconds}ms',
        );
      } catch (e) {
        debugPrint('  ${entry.key} | ERROR | $e');
      }
    }
    debugPrint('══════════════════════════════════════════');
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
