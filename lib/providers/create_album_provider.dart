import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'album_participation_provider.dart';

/// 1. 表单数据模型
class CreateAlbumForm {
  final String name;
  final String password;
  final String nickname;
  final String shareCode;

  CreateAlbumForm({
    required this.name,
    required this.password,
    required this.nickname,
    required this.shareCode,
  });
}

/// 2. Riverpod 2.x 标准异步状态管理器 (直接继承 AsyncNotifier)
class CreateAlbumNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    // 初始状态为空
    return null;
  }

  /// 客户端密码 SHA-256 哈希
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// 随机生成 6 位相册分享码（防碰撞备用）
  String _generateRandomShareCode() {
    const chars = '0123456789';
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// 执行创建相册并入库
  Future<void> submitAlbum(CreateAlbumForm form) async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;

    if (currentUser == null) {
      state = AsyncValue.error('操作中止：创建相册必须先登录！', StackTrace.current);
      return;
    }

    // 2.x 干净的加载中状态切换
    state = const AsyncValue.loading();

    // 利用 AsyncValue.guard 捕获异步结果
    state = await AsyncValue.guard(() async {
      final now = DateTime.now().toUtc();
      final expiresAt = now.add(const Duration(hours: 24));

      var shareCode = form.shareCode;
      var inserted = false;
      var retries = 0;

      while (!inserted && retries < 3) {
        try {
          // 2. 写入 albums 表
          await supabase.from('albums').insert({
            'name': form.name.trim(),
            'share_code': shareCode,
            'password_hash': _hashPassword(form.password),
            'creator_id': currentUser.id,
            'expires_at': expiresAt.toIso8601String(),
          });
          inserted = true;

          // 3. 创建成功后，查询 album ID 并写入参与关系
          final albumResponse = await supabase
              .from('albums')
              .select('id')
              .eq('share_code', shareCode)
              .single();
          final albumId = albumResponse['id'] as String;

          await recordAlbumParticipation(
            albumId: albumId,
            userId: currentUser.id,
            relationType: 'creator',
          );
        } catch (e) {
          // 如果是唯一键冲突（Postgres 错误码 23505），尝试重新生成分享码
          if (e is PostgrestException && e.code == '23505' && retries < 2) {
            shareCode = _generateRandomShareCode();
            retries++;
          } else {
            rethrow;
          }
        }
      }

      return shareCode;
    });
  }
}

/// 3. 2.x 版本的 autoDispose 暴露方式
final createAlbumProvider =
    AsyncNotifierProvider.autoDispose<CreateAlbumNotifier, String?>(
      CreateAlbumNotifier.new,
    );
