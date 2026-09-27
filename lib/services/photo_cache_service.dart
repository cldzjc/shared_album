import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../providers/album_photos_provider.dart';
import 'photo_image_service.dart';

/// 统一缓存管理服务
///
/// 不自己实现 LRU，全部委托给 flutter_cache_manager。
/// 本服务只负责：清除指定 URL、清除指定相册、统计、预热。
class PhotoCacheService {
  /// 缩略图缓存（全局，使用 cached_network_image 默认管理器）
  static final DefaultCacheManager thumbnails = DefaultCacheManager();

  /// 预览原图缓存（独立实例，容量约 200MB，LRU 自动淘汰）
  /// 平均单张原图 3-6MB，限制约 35-65 张，总计控制在 ~200MB
  static final CacheManager previews = CacheManager(
    Config(
      'preview_originals',
      stalePeriod: const Duration(days: 1),
      maxNrOfCacheObjects: 50,
    ),
  );

  // ── 清除 ──

  /// 清除单张照片的全部缓存（缩略图 + 预览原图）
  static Future<void> clearPhoto(PhotoModel photo) async {
    await thumbnails.removeFile(PhotoImageService.getThumbnail(photo.fileUrl));
    await previews.removeFile(PhotoImageService.getPreview(photo.fileUrl));
  }

  /// 清除整个相册的全部缓存
  static Future<void> clearAlbum(List<PhotoModel> photos) async {
    for (final photo in photos) {
      await clearPhoto(photo);
    }
  }

  /// 清除缩略图缓存
  static Future<void> clearPhotoThumbnail(PhotoModel photo) async {
    await thumbnails.removeFile(PhotoImageService.getThumbnail(photo.fileUrl));
  }

  // ── 预热 ──

  /// 预加载下一批缩略图（后台静默下载）
  /// [photos] 全部照片列表，[startIndex] 起始索引，[count] 数量
  static Future<void> prefetchThumbnails(
    List<PhotoModel> photos, {
    int startIndex = 0,
    int count = 9,
  }) async {
    final end = (startIndex + count).clamp(0, photos.length);
    final batch = photos.sublist(startIndex, end);
    for (final photo in batch) {
      try {
        await thumbnails.downloadFile(
          PhotoImageService.getThumbnail(photo.fileUrl),
        );
      } catch (_) {
        // 预热失败不影响浏览
      }
    }
  }
}
