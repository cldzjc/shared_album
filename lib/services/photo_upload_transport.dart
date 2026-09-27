import 'dart:typed_data';

import 'photo_upload_transport_io.dart'
    if (dart.library.js_interop) 'photo_upload_transport_web.dart'
    as impl;

/// 照片上传传输层（平台分派）
///
/// - Android / iOS：沿用原有 `http.put` 直传逻辑，行为不变。
/// - Web：使用浏览器 XMLHttpRequest 上传，通过 upload 进度事件回报真实字节进度。
///
/// 注意：`contentType` 必须与 `oss-sign-upload` Edge Function 签名时使用的
/// Content-Type 完全一致，否则 OSS 会返回 SignatureDoesNotMatch。
Future<void> putBytes({
  required String uploadUrl,
  required Uint8List bytes,
  required String contentType,
  void Function(double progress)? onProgress,
}) {
  return impl.putBytes(
    uploadUrl: uploadUrl,
    bytes: bytes,
    contentType: contentType,
    onProgress: onProgress,
  );
}
