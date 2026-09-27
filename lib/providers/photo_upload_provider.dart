import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../services/photo_upload_service.dart';
import '../services/supabase_client_manager.dart';

/// 上传状态定义
class PhotoUploadState {
  final bool isUploading;
  final double progress; // 0.0 - 1.0
  final String? successMessage;
  final String? errorMessage;

  PhotoUploadState({
    this.isUploading = false,
    this.progress = 0.0,
    this.successMessage,
    this.errorMessage,
  });

  PhotoUploadState copyWith({
    bool? isUploading,
    double? progress,
    String? successMessage,
    String? errorMessage,
  }) {
    return PhotoUploadState(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      successMessage: successMessage,
      errorMessage: errorMessage,
    );
  }
}

/// 单个相册的照片上传 Notifier
class PhotoUploadNotifier extends Notifier<PhotoUploadState> {
  final String albumId;
  final PhotoUploadService _uploadService = PhotoUploadService();

  PhotoUploadNotifier(this.albumId);

  @override
  PhotoUploadState build() {
    return PhotoUploadState();
  }

  /// 从相册选择并上传一张照片。
  /// 返回 true 表示真实完成了选图并进入上传流程（供调用方决定是否刷新列表）；
  /// 返回 false 表示用户取消选择或流程失败，不需要刷新列表。
  Future<bool> pickAndUploadSinglePhoto() async {
    try {
      // ⚠️ 重要：选图必须紧跟用户手势（iOS Safari 要求同步触发文件选择器），
      // 任何网络请求一律放在选图之后执行；选图前也不进入 isUploading，
      // 避免系统选择器弹出时按钮背后出现“上传中”药丸。
      final imageFile = await _uploadService.pickImage();
      if (imageFile == null) {
        return false; // 用户取消：状态保持原样
      }

      state = state.copyWith(
        isUploading: true,
        progress: 0.0,
        errorMessage: null,
        successMessage: null,
      );

      // 免费版上限：已满则不再上传，直接提示
      final existingCount = await _existingPhotoCount();
      if (existingCount >= AppConfig.maxPhotosPerFreeAlbum) {
        throw Exception(_limitReachedMessage(existingCount));
      }

      state = state.copyWith(progress: 0.3);

      final currentUser = SupabaseClientManager.client.auth.currentUser;

      // 上传需要正式用户，通过读 profiles.account_type 判断
      final isNormal = await _isNormalUser(currentUser?.id);
      if (!isNormal) {
        throw Exception('上传照片需要正式账号，请先升级身份');
      }

      await _uploadService.uploadAndSave(
        imageFile: imageFile,
        albumId: albumId,
        uploaderId: currentUser!.id,
        onProgress: (progress) {
          if (!ref.mounted) return;
          state = state.copyWith(
            progress: (0.3 + progress * 0.7).clamp(0.0, 1.0),
          );
        },
      );

      state = state.copyWith(
        isUploading: false,
        progress: 1.0,
        successMessage: '照片上传成功！',
      );

      await Future.delayed(const Duration(seconds: 2));
      state = PhotoUploadState();
      return true;
    } catch (e) {
      state = state.copyWith(isUploading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// 从相册选择并上传多张照片。
  /// 返回 true 表示真实完成了选图并进入上传流程（供调用方决定是否刷新列表）；
  /// 返回 false 表示用户取消选择或流程失败，不需要刷新列表。
  Future<bool> pickAndUploadMultiplePhotos() async {
    try {
      // ⚠️ 重要：选图必须紧跟用户手势（iOS Safari 要求同步触发文件选择器），
      // 任何网络请求一律放在选图之后执行；选图前也不进入 isUploading，
      // 避免系统选择器弹出时按钮背后出现“上传中”药丸。
      final imageFiles = await _uploadService.pickMultipleImages();
      if (imageFiles.isEmpty) {
        return false; // 用户取消：状态保持原样，不触发列表刷新
      }

      state = state.copyWith(
        isUploading: true,
        progress: 0.0,
        errorMessage: null,
        successMessage: null,
      );

      // 免费版上限：已满则不再上传，直接提示
      final existingCount = await _existingPhotoCount();
      if (existingCount >= AppConfig.maxPhotosPerFreeAlbum) {
        throw Exception(_limitReachedMessage(existingCount));
      }

      // 选择数量超出剩余名额时截断，并给出明确提示
      final remaining = AppConfig.maxPhotosPerFreeAlbum - existingCount;
      var filesToUpload = imageFiles;
      String? limitNotice;
      if (imageFiles.length > remaining) {
        filesToUpload = imageFiles.sublist(0, remaining);
        limitNotice =
            '超出免费版 ${AppConfig.maxPhotosPerFreeAlbum} 张上限，'
            '本次仅上传前 $remaining 张';
      }

      final currentUser = SupabaseClientManager.client.auth.currentUser;

      final isNormal = await _isNormalUser(currentUser?.id);
      if (!isNormal) {
        throw Exception('上传照片需要正式账号，请先升级身份');
      }

      for (int i = 0; i < filesToUpload.length; i++) {
        final index = i;
        await _uploadService.uploadAndSave(
          imageFile: filesToUpload[i],
          albumId: albumId,
          uploaderId: currentUser!.id,
          onProgress: (progress) {
            if (!ref.mounted) return;
            state = state.copyWith(
              progress: ((index + progress) / filesToUpload.length).clamp(
                0.0,
                1.0,
              ),
            );
          },
        );
        if (!ref.mounted) return false;
        state = state.copyWith(progress: (i + 1) / filesToUpload.length);
      }

      state = state.copyWith(
        isUploading: false,
        successMessage: limitNotice ?? '${filesToUpload.length} 张照片上传成功！',
      );

      await Future.delayed(const Duration(seconds: 2));
      state = PhotoUploadState();
      return true;
    } catch (e) {
      state = state.copyWith(isUploading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// 通过 profiles 表检查当前用户是否是正式用户
  Future<bool> _isNormalUser(String? userId) async {
    if (userId == null) return false;
    try {
      final response = await SupabaseClientManager.client
          .from('profiles')
          .select('account_type')
          .eq('id', userId)
          .maybeSingle();
      return response?['account_type'] == 'normal';
    } catch (_) {
      return false;
    }
  }

  /// 查询该相册当前已有照片数（免费版上限校验用）。
  /// 只取 id 列，相册最多 50 张，开销可忽略。
  Future<int> _existingPhotoCount() async {
    try {
      final rows = await SupabaseClientManager.client
          .from('photos')
          .select('id')
          .eq('album_id', albumId);
      return (rows as List).length;
    } catch (_) {
      // 查询失败时不阻断上传，后端 Edge Function 仍会兜底校验
      return 0;
    }
  }

  String _limitReachedMessage(int existingCount) {
    return '该相册已有 $existingCount 张照片，'
        '达到免费版 ${AppConfig.maxPhotosPerFreeAlbum} 张上限，无法继续上传';
  }

  /// 清空上传状态
  void clearState() {
    state = PhotoUploadState();
  }
}

/// Family autoDispose 状态管理，针对不同相册隔离上传状态
final photoUploadProvider = NotifierProvider.autoDispose
    .family<PhotoUploadNotifier, PhotoUploadState, String>(
      (albumId) => PhotoUploadNotifier(albumId),
    );
