import 'package:supabase_flutter/supabase_flutter.dart';

/// 照片删除服务 - 只负责调用统一的 delete-resource Edge Function
class PhotoDeleteService {
  final SupabaseClient supabase = Supabase.instance.client;

  static const String _edgeFunctionName = 'delete-resource';

  Future<void> deletePhoto({required String photoId}) async {
    try {
      final response = await supabase.functions.invoke(
        _edgeFunctionName,
        body: <String, dynamic>{'resourceType': 'photo', 'photoId': photoId},
      );

      final data = response.data;
      if (data is Map) {
        final isSuccess = data['success'] == true;
        if (isSuccess) {
          return;
        }

        final message = data['message']?.toString();
        throw Exception(message ?? '删除照片失败');
      }

      throw Exception('删除照片失败：返回结果格式异常');
    } catch (error) {
      throw Exception('删除照片失败: $error');
    }
  }
}
