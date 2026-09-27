import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../services/photo_download_service.dart';

/// 照片下载状态定义
class PhotoDownloadState {
  final bool isDownloading;
  final double downloadProgress; // 0.0 - 1.0
  final String? successMessage;
  final String? errorMessage;
  final bool isDownloaded; // 是否已下载到本地

  PhotoDownloadState({
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.successMessage,
    this.errorMessage,
    this.isDownloaded = false,
  });

  PhotoDownloadState copyWith({
    bool? isDownloading,
    double? downloadProgress,
    String? successMessage,
    String? errorMessage,
    bool? isDownloaded,
  }) {
    return PhotoDownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      successMessage: successMessage,
      errorMessage: errorMessage,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }
}

/// 单张照片的下载 Notifier
class PhotoDownloadNotifier extends Notifier<PhotoDownloadState> {
  final String photoUrl;
  final String photoFileName;
  final PhotoDownloadService _downloadService = PhotoDownloadService();

  PhotoDownloadNotifier({required this.photoUrl, required this.photoFileName});

  @override
  PhotoDownloadState build() {
    // 初始化时检查是否已下载
    _checkIfDownloaded();
    return PhotoDownloadState();
  }

  /// 检查照片是否已下载
  Future<void> _checkIfDownloaded() async {
    try {
      final isDownloaded = await _downloadService.isPhotoDownloaded(
        fileName: photoFileName,
      );
      if (!ref.mounted) {
        return;
      }
      if (isDownloaded) {
        state = state.copyWith(isDownloaded: true);
      }
    } catch (_) {
      // 忽略检查错误
    }
  }

  /// 下载照片
  Future<void> downloadPhoto() async {
    final keepAliveLink = ref.keepAlive();

    try {
      state = state.copyWith(
        isDownloading: true,
        errorMessage: null,
        successMessage: null,
        downloadProgress: 0.0,
      );

      final filePath = await _downloadService.downloadPhoto(
        fileUrl: photoUrl,
        fileName: photoFileName,
        onProgress: (progress) {
          if (!ref.mounted) {
            return;
          }
          state = state.copyWith(
            isDownloading: true,
            downloadProgress: progress,
          );
        },
      );

      if (!ref.mounted) {
        return;
      }

      if (filePath != null) {
        state = state.copyWith(
          isDownloading: false,
          isDownloaded: true,
          downloadProgress: 1.0,
          successMessage: kIsWeb ? '照片已开始下载' : '照片已保存到相册库',
        );

        // 2 秒后清空成功提示
        await Future.delayed(const Duration(seconds: 2));
        if (!ref.mounted) {
          return;
        }
        state = state.copyWith(successMessage: null);
      }
    } catch (e) {
      debugPrint('PhotoDownloadNotifier.downloadPhoto failed: $e');
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: state.isDownloaded ? 1.0 : 0.0,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      keepAliveLink.close();
    }
  }

  /// 清空状态
  void clearState() {
    state = PhotoDownloadState(isDownloaded: state.isDownloaded);
  }
}

/// Family autoDispose provider - 针对不同照片隔离下载状态
final photoDownloadProvider = NotifierProvider.autoDispose
    .family<PhotoDownloadNotifier, PhotoDownloadState, (String, String)>(
      (arg) => PhotoDownloadNotifier(photoUrl: arg.$1, photoFileName: arg.$2),
    );
