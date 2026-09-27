import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 1. 照片数据模型
class PhotoModel {
  final String id;
  final String albumId;
  final String fileUrl;
  final String storagePath;
  final String? uploaderId;
  final DateTime createdAt;

  PhotoModel({
    required this.id,
    required this.albumId,
    required this.fileUrl,
    required this.storagePath,
    this.uploaderId,
    required this.createdAt,
  });

  factory PhotoModel.fromMap(Map<String, dynamic> map) {
    return PhotoModel(
      id: map['id'] as String,
      albumId: map['album_id'] as String,
      fileUrl: map['file_url'] as String,
      storagePath: map['storage_path'] as String,
      uploaderId: map['uploader_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// 2. 针对指定相册的照片流状态管理器 (Riverpod 3.0 手动 Family 规范)
class AlbumPhotosNotifier extends AsyncNotifier<List<PhotoModel>> {
  final String albumId;

  AlbumPhotosNotifier(this.albumId);

  @override
  Future<List<PhotoModel>> build() async {
    return _fetchPhotos(albumId);
  }

  /// 从 Supabase 查询照片列表，按创建时间倒序排列
  Future<List<PhotoModel>> _fetchPhotos(String id) async {
    final supabase = Supabase.instance.client;
    final response = await supabase
        .from('photos')
        .select()
        .eq('album_id', id)
        .order('created_at', ascending: false);

    // 方案 A：file_url 已是 OSS 可访问地址，列表页不再依赖 Supabase Storage 签名。
    return (response as List)
        .map((item) => PhotoModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  /// 刷新照片列表
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchPhotos(albumId));
  }
}

/// 3. Family autoDispose 状态暴露，确保各个相册的图片列表隔离，页面关闭时自动销毁
final albumPhotosProvider = AsyncNotifierProvider.autoDispose
    .family<AlbumPhotosNotifier, List<PhotoModel>, String>(
      (albumId) => AlbumPhotosNotifier(albumId),
    );
