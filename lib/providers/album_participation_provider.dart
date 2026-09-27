import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'join_album_provider.dart';

class AlbumParticipationEntry {
  final AlbumModel album;
  final String relationType;
  final DateTime? joinedAt;

  /// 相册封面：相册内第一张（最早）照片的原始 file_url，供首页列表缩略图展示
  final String? coverPhotoUrl;

  AlbumParticipationEntry({
    required this.album,
    required this.relationType,
    this.joinedAt,
    this.coverPhotoUrl,
  });

  bool get isCreator => relationType == 'creator';
}

Future<void> recordAlbumParticipation({
  required String albumId,
  required String userId,
  required String relationType,
}) async {
  final supabase = Supabase.instance.client;

  await supabase.from('album_participants').upsert({
    'album_id': albumId,
    'user_id': userId,
    'role': relationType,
    'joined_at': DateTime.now().toUtc().toIso8601String(),
  }, onConflict: 'album_id,user_id');
}

class MyAlbumsNotifier extends AsyncNotifier<List<AlbumParticipationEntry>> {
  final String userId;

  MyAlbumsNotifier(this.userId);

  @override
  Future<List<AlbumParticipationEntry>> build() async {
    return _fetchMyAlbums(userId);
  }

  Future<List<AlbumParticipationEntry>> _fetchMyAlbums(String id) async {
    if (id.isEmpty) {
      return [];
    }

    final supabase = Supabase.instance.client;
    var entries = <AlbumParticipationEntry>[];
    final seenAlbumIds = <String>{};

    final createdResponse = await supabase
        .from('albums')
        .select()
        .eq('creator_id', id)
        .order('created_at', ascending: false);

    for (final item in createdResponse as List) {
      final album = AlbumModel.fromMap(item as Map<String, dynamic>);
      if (seenAlbumIds.add(album.id)) {
        entries.add(
          AlbumParticipationEntry(
            album: album,
            relationType: 'creator',
            joinedAt: album.createdAt,
          ),
        );
      }
    }

    final participantResponse = await supabase
        .from('album_participants')
        .select('joined_at, role, album:albums(*)')
        .eq('user_id', id)
        .order('joined_at', ascending: false);

    for (final item in participantResponse as List) {
      final row = item as Map<String, dynamic>;
      final albumMap = row['album'];
      if (albumMap is! Map<String, dynamic>) {
        continue;
      }

      final album = AlbumModel.fromMap(albumMap);
      if (!seenAlbumIds.add(album.id)) {
        continue;
      }

      entries.add(
        AlbumParticipationEntry(
          album: album,
          relationType: row['role'] as String? ?? 'member',
          joinedAt: row['joined_at'] == null
              ? null
              : DateTime.parse(row['joined_at'] as String),
        ),
      );
    }

    // 3. 批量获取每个相册的封面：一次 in 查询拿全部照片（只取 3 个字段），
    //    本地取每组 created_at 最早的一张（相册第一张照片），避免 N+1 查询。
    final albumIds = entries.map((e) => e.album.id).toList();
    if (albumIds.isNotEmpty) {
      try {
        final photosResponse = await supabase
            .from('photos')
            .select('album_id, file_url, created_at')
            .inFilter('album_id', albumIds)
            .order('created_at', ascending: true);

        final rows = photosResponse as List;
        if (rows.isEmpty) {
          debugPrint('[Home Cover] 封面查询返回空，albumIds: $albumIds');
        }

        final coverByAlbum = <String, String>{};
        for (final item in rows) {
          final row = item as Map<String, dynamic>;
          final albumIdOfPhoto = row['album_id'] as String?;
          final fileUrl = row['file_url'] as String?;
          if (albumIdOfPhoto != null && fileUrl != null) {
            coverByAlbum.putIfAbsent(albumIdOfPhoto, () => fileUrl);
          }
        }

        entries = entries.map((e) {
          final cover = coverByAlbum[e.album.id];
          if (cover == null) return e;
          return AlbumParticipationEntry(
            album: e.album,
            relationType: e.relationType,
            joinedAt: e.joinedAt,
            coverPhotoUrl: cover,
          );
        }).toList();
      } catch (e) {
        // 封面查询失败不阻断列表展示，但记录原因便于排查
        debugPrint('[Home Cover] 封面查询失败（不影响列表）: $e');
      }
    }

    return entries;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchMyAlbums(userId));
  }
}

final myAlbumsProvider = AsyncNotifierProvider.autoDispose
    .family<MyAlbumsNotifier, List<AlbumParticipationEntry>, String>(
      (userId) => MyAlbumsNotifier(userId),
    );
