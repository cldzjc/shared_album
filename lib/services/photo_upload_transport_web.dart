import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web 上传实现：使用浏览器 XMLHttpRequest 直传 OSS，
/// 通过 upload 进度事件回报真实字节进度（package:http 在 Web 上无法提供）。
Future<void> putBytes({
  required String uploadUrl,
  required Uint8List bytes,
  required String contentType,
  void Function(double progress)? onProgress,
}) {
  final completer = Completer<void>();
  final xhr = web.XMLHttpRequest();

  xhr.open('PUT', uploadUrl);
  // 必须与 oss-sign-upload 签名时使用的 Content-Type 完全一致
  xhr.setRequestHeader('Content-Type', contentType);

  xhr.upload.addEventListener(
    'progress',
    ((web.ProgressEvent event) {
      if (event.lengthComputable && event.total > 0) {
        onProgress?.call(event.loaded / event.total);
      }
    }).toJS,
  );

  xhr.addEventListener(
    'load',
    ((web.Event event) {
      final status = xhr.status;
      if (status >= 200 && status < 300) {
        onProgress?.call(1.0);
        completer.complete();
      } else {
        completer.completeError(
          Exception('OSS 上传失败: HTTP $status ${xhr.responseText}'),
        );
      }
    }).toJS,
  );

  xhr.addEventListener(
    'error',
    ((web.Event event) {
      completer.completeError(Exception('OSS 上传失败: 网络错误'));
    }).toJS,
  );

  xhr.addEventListener(
    'abort',
    ((web.Event event) {
      completer.completeError(Exception('OSS 上传失败: 已中止'));
    }).toJS,
  );

  xhr.addEventListener(
    'timeout',
    ((web.Event event) {
      completer.completeError(Exception('OSS 上传失败: 请求超时'));
    }).toJS,
  );

  xhr.send(bytes.toJS);
  return completer.future;
}
