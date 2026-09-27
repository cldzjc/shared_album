import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'photo_upload_transport.dart';

/// 照片上传服务 - 处理文件上传和数据库记录
class PhotoUploadService {
  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  static const String _edgeFunctionName = 'oss-sign-upload';

  /// 从手机相册选择单张照片
  Future<XFile?> pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // 压缩质量到 85%
      );
      return image;
    } catch (e) {
      throw Exception('选择照片失败: $e');
    }
  }

  /// 从手机相册选择多张照片
  Future<List<XFile>> pickMultipleImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
      );
      return images;
    } catch (e) {
      throw Exception('选择照片失败: $e');
    }
  }

  /// 上传单张照片：返回 (file_url, storage_path)
  Future<(String fileUrl, String storagePath)> uploadPhoto({
    required XFile imageFile,
    required String albumId,
    required String uploaderId,
    void Function(double progress)? onProgress,
  }) async {
    try {
      // 1. 跨平台读取字节：iOS/Android 读真实文件，Web 读 Blob
      final fileBytes = await imageFile.readAsBytes();
      final contentType = _detectContentType(imageFile.name);

      // 2. 调用 Edge Function 获取 OSS 预签名上传地址
      final signResponse = await supabase.functions.invoke(
        _edgeFunctionName,
        body: {
          'filename': imageFile.name,
          'contentType': contentType,
          'album_id': albumId,
          'uploader_id': uploaderId,
        },
      );

      final data = signResponse.data;
      if (data is! Map) {
        throw Exception('Edge Function 返回格式错误');
      }

      final uploadUrl = data['uploadUrl'] as String?;
      final publicUrl = data['publicUrl'] as String?;
      final objectKey = data['objectKey'] as String?;

      if (uploadUrl == null || publicUrl == null || objectKey == null) {
        throw Exception('Edge Function 返回缺少 uploadUrl/publicUrl/objectKey');
      }

      // 3. 直传 OSS（平台传输层：IO 沿用 http.put，Web 走 XHR + 进度）
      await putBytes(
        uploadUrl: uploadUrl,
        bytes: fileBytes,
        contentType: contentType,
        onProgress: onProgress,
      );

      // 4. 返回可直接访问的 OSS URL 与对象路径
      return (publicUrl, objectKey);
    } catch (e) {
      throw Exception('上传照片失败: $e');
    }
  }

  /// 将照片元数据写入数据库
  Future<void> savephotometadata({
    required String albumId,
    required String fileUrl,
    required String storagePath,
    required String uploaderId,
  }) async {
    try {
      await supabase.from('photos').insert({
        'album_id': albumId,
        'file_url': fileUrl,
        'storage_path': storagePath,
        'uploader_id': uploaderId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('保存照片信息失败: $e');
    }
  }

  String _detectContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  /// 一键上传：选择文件 → 上传到 Storage → 保存到数据库
  Future<void> uploadAndSave({
    required XFile imageFile,
    required String albumId,
    required String uploaderId,
    void Function(double progress)? onProgress,
  }) async {
    final (fileUrl, storagePath) = await uploadPhoto(
      imageFile: imageFile,
      albumId: albumId,
      uploaderId: uploaderId,
      onProgress: onProgress,
    );

    await savephotometadata(
      albumId: albumId,
      fileUrl: fileUrl,
      storagePath: storagePath,
      uploaderId: uploaderId,
    );
  }
}
