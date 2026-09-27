import 'photo_download_service_io.dart'
    if (dart.library.js_interop) 'photo_download_service_web.dart'
    as impl;

/// 照片下载服务（平台分派）
///
/// - Android / iOS：下载到本地沙盒并保存到系统相册（原逻辑不变，
///   见 photo_download_service_io.dart）。
/// - Web：GET → bytes → Blob → Object URL → 触发浏览器文件下载
///   （见 photo_download_service_web.dart），不写本地文件系统。
class PhotoDownloadService {
  /// 下载照片。
  /// 返回：IO 端返回本地文件路径；Web 端返回 fileName（非空表示下载已触发）。
  Future<String?> downloadPhoto({
    required String fileUrl,
    required String fileName,
    void Function(double progress)? onProgress,
  }) {
    return impl.downloadPhoto(
      fileUrl: fileUrl,
      fileName: fileName,
      onProgress: onProgress,
    );
  }

  /// 照片是否已下载到本地（Web 恒为 false）。
  Future<bool> isPhotoDownloaded({required String fileName}) {
    return impl.isPhotoDownloaded(fileName: fileName);
  }
}
