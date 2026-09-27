import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 1. 相册数据模型
class AlbumModel {
  final String id;
  final String name;
  final String shareCode;
  final String creatorId;
  final DateTime expiresAt;
  final DateTime createdAt;

  AlbumModel({
    required this.id,
    required this.name,
    required this.shareCode,
    required this.creatorId,
    required this.expiresAt,
    required this.createdAt,
  });

  factory AlbumModel.fromMap(Map<String, dynamic> map) {
    return AlbumModel(
      id: map['id'] as String,
      name: map['name'] as String,
      shareCode: map['share_code'] as String,
      creatorId: map['creator_id'] as String,
      expiresAt: DateTime.parse(map['expires_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// 2. 加入相册状态管理器 — 全部逻辑下沉到 RPC，Flutter 不接触 albums / password_hash
class JoinAlbumNotifier extends AsyncNotifier<AlbumModel?> {
  @override
  Future<AlbumModel?> build() async {
    return null;
  }

  /// 校验分享码与密码并加入相册 — 仅调用一个 Security Definer RPC
  Future<AlbumModel> joinAlbum(String shareCode, String password) async {
    state = const AsyncValue.loading();

    state = await AsyncValue.guard(() async {
      final supabase = Supabase.instance.client;

      final result = await supabase.rpc(
        'verify_and_join_album',
        params: {
          'input_share_code': shareCode.trim(),
          'input_password': password,
        },
      );

      if (result is! Map<String, dynamic>) {
        throw Exception('服务器返回格式异常，请稍后重试');
      }

      final success = result['success'] == true;
      if (!success) {
        final message = (result['message'] as String?) ?? '加入相册失败，请稍后重试';
        throw Exception(message);
      }

      final albumMap = result['album'];
      if (albumMap is! Map<String, dynamic>) {
        throw Exception('服务器返回异常：缺少相册信息');
      }

      return AlbumModel.fromMap(albumMap);
    });

    if (state.hasError) {
      throw state.error!;
    }

    return state.requireValue!;
  }
}

/// 3. autoDispose 状态暴露
final joinAlbumProvider =
    AsyncNotifierProvider.autoDispose<JoinAlbumNotifier, AlbumModel?>(
      JoinAlbumNotifier.new,
    );
