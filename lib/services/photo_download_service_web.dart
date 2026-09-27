import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Web 平台下载实现：
/// GET 图片 → 收集 bytes → Blob → Object URL → 触发浏览器文件下载。
/// 不使用 dart:io / path_provider / Gal，不写入本地文件系统。
Future<String?> downloadPhoto({
  required String fileUrl,
  required String fileName,
  void Function(double progress)? onProgress,
}) async {
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(fileUrl)));

    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength;
    final builder = BytesBuilder(copy: false);
    var receivedBytes = 0;

    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      builder.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes != null && totalBytes > 0) {
        onProgress?.call(receivedBytes / totalBytes);
      }
    }

    final bytes = builder.takeBytes();
    final contentType =
        _contentTypeFromHeaders(response.headers['content-type']) ??
        _detectContentType(fileName);

    final blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: contentType),
    );
    final objectUrl = web.URL.createObjectURL(blob);

    final anchor = web.HTMLAnchorElement()
      ..href = objectUrl
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();

    // 下载已由浏览器接管后，延迟释放 Object URL，避免过早释放导致下载中断
    Timer(const Duration(seconds: 60), () {
      web.URL.revokeObjectURL(objectUrl);
    });

    onProgress?.call(1.0);
    return fileName;
  } catch (e) {
    throw Exception('照片下载失败: $e');
  } finally {
    client.close();
  }
}

/// Web 端不存在“已下载到本地文件”的概念，恒为 false。
Future<bool> isPhotoDownloaded({required String fileName}) async => false;

String? _contentTypeFromHeaders(String? value) {
  if (value == null) return null;
  final type = value.split(';').first.trim().toLowerCase();
  return type.startsWith('image/') ? type : null;
}

String _detectContentType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}
