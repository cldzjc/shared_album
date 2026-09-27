import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 相册参与者条目（用于相册详情页"参与者"面板）
class AlbumMemberModel {
  final String userId;

  /// 'creator' 或 'member'
  final String role;
  final DateTime joinedAt;

  AlbumMemberModel({
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  bool get isCreator => role == 'creator';
}

/// 相册参与者列表状态管理器
///
/// 展示规则：
/// - 按 joined_at 升序排列（从上到下 = 加入时间先后）；
/// - 创建者始终存在（来自 albums.creator_id，即使 albums 查询失败也不会丢）；
/// - 游客/非成员访问时 album_participants 被 RLS 拦截，返回降级列表（仅创建者）。
class AlbumMembersNotifier extends AsyncNotifier<List<AlbumMemberModel>> {
  final String albumId;

  AlbumMembersNotifier(this.albumId);

  @override
  Future<List<AlbumMemberModel>> build() async {
    return _fetchMembers();
  }

  Future<List<AlbumMemberModel>> _fetchMembers() async {
    final supabase = Supabase.instance.client;
    final members = <AlbumMemberModel>[];

    // 1. 读取相册信息（创建者 + 创建时间），用于兜底补齐创建者
    try {
      final albumRow = await supabase
          .from('albums')
          .select('creator_id, created_at')
          .eq('id', albumId)
          .maybeSingle();

      if (albumRow != null) {
        final creatorId = albumRow['creator_id'] as String?;
        final createdAtRaw = albumRow['created_at'] as String?;
        if (creatorId != null && creatorId.isNotEmpty) {
          members.add(
            AlbumMemberModel(
              userId: creatorId,
              role: 'creator',
              joinedAt: createdAtRaw != null
                  ? DateTime.parse(createdAtRaw)
                  : DateTime.now().toUtc(),
            ),
          );
        }
      }
    } catch (_) {
      // albums 查询失败（无权限）时继续尝试参与者查询
    }

    // 2. 读取参与者列表，按加入时间升序
    try {
      final response = await supabase
          .from('album_participants')
          .select('user_id, role, joined_at')
          .eq('album_id', albumId)
          .order('joined_at', ascending: true);

      for (final item in response as List) {
        final row = item as Map<String, dynamic>;
        final userId = row['user_id'] as String?;
        final role = row['role'] as String? ?? 'member';
        final joinedAt = row['joined_at'] == null
            ? null
            : DateTime.tryParse(row['joined_at'] as String);

        if (userId == null || userId.isEmpty) continue;

        // 与第 1 步的创建者去重
        final existingIndex = members.indexWhere((m) => m.userId == userId);
        if (existingIndex != -1) {
          if (role == 'creator') {
            members[existingIndex] = AlbumMemberModel(
              userId: userId,
              role: 'creator',
              joinedAt: joinedAt ?? members[existingIndex].joinedAt,
            );
          }
          continue;
        }

        members.add(
          AlbumMemberModel(
            userId: userId,
            role: role,
            joinedAt: joinedAt ?? DateTime.now().toUtc(),
          ),
        );
      }
    } catch (_) {
      // 游客/非成员被 RLS 拦截：仅保留创建者兜底数据
    }

    members.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    return members;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetchMembers);
  }
}

/// autoDispose family：每个相册的参与者列表隔离，页面关闭自动销毁
final albumMembersProvider = AsyncNotifierProvider.autoDispose
    .family<AlbumMembersNotifier, List<AlbumMemberModel>, String>(
      (albumId) => AlbumMembersNotifier(albumId),
    );
