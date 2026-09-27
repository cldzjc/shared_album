import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../providers/album_members_provider.dart';
import '../providers/join_album_provider.dart';
import '../providers/album_photos_provider.dart';
import '../providers/album_expiry_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/photo_upload_provider.dart';
import '../services/guest_session_manager.dart';
import '../services/photo_cache_service.dart';
import '../services/photo_image_service.dart';
import '../widgets/album_countdown_widget.dart';
import '../widgets/ios_toast.dart';
import 'photo_viewer_page.dart';

class AlbumDetailPage extends ConsumerStatefulWidget {
  final AlbumModel album;

  const AlbumDetailPage({super.key, required this.album});

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage> {
  AlbumModel get album => widget.album;

  final ScrollController _scrollController = ScrollController();
  int _prefetchedCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    // 距底部 300px 时触发预加载
    if (maxScroll - current < 300) {
      final photosState = ref.read(albumPhotosProvider(album.id));
      final photos = photosState.hasValue ? photosState.value : null;
      if (photos == null || photos.isEmpty) return;

      final nextStart = _prefetchedCount;
      if (nextStart < photos.length) {
        _prefetchedCount = (nextStart + 9).clamp(0, photos.length);
        PhotoCacheService.prefetchThumbnails(
          photos,
          startIndex: nextStart,
          count: 9,
        );
      }
    }
  }

  void _showLoginRequiredDialog(BuildContext context, String actionLabel) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$actionLabel 需要登录'),
        content: Text('游客可以浏览相册内容，但 $actionLabel 属于需要身份的操作。\n\n请先登录后再继续。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).pushNamed('/login');
            },
            child: const Text('去登录/注册'),
          ),
        ],
      ),
    );
  }

  void _handleUpload(BuildContext context) async {
    final authState = ref.read(authProvider).value;

    if (!GuestSessionManager.canExecuteFromState(
      IdentityAction.uploadPhoto,
      authState,
    )) {
      _showLoginRequiredDialog(context, '上传照片');
      return;
    }

    // 免费版上限：已满则直接提示，不打开系统选择器
    final currentPhotos = ref.read(albumPhotosProvider(album.id)).value ?? [];
    if (currentPhotos.length >= AppConfig.maxPhotosPerFreeAlbum) {
      showIosToast(
        context,
        '该相册已达到免费版 ${AppConfig.maxPhotosPerFreeAlbum} 张上限，无法继续上传',
        isError: true,
      );
      return;
    }

    // 直接调用多图上传（用户选几张就是几张，选一张就自动变成单图）。
    // 返回 true（真实上传完成）才刷新列表；取消选图不刷新，避免空状态闪变。
    ref
        .read(photoUploadProvider(album.id).notifier)
        .pickAndUploadMultiplePhotos()
        .then((uploaded) {
          if (!uploaded || !mounted) return;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              ref.read(albumPhotosProvider(album.id).notifier).refresh();
            }
          });
        });
  }

  /// 参与者面板：按加入时间从上到下排列，标记创建者/参与者
  void _showMembersSheet(
    AsyncValue<List<AlbumMemberModel>> membersState,
    String? myUserId,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final memberCount = membersState.hasValue
            ? membersState.value!.length
            : null;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      '相册参与者',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      memberCount == null ? '加载中...' : '$memberCount 人',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '按加入时间先后排列 · 仅展示用户 ID',
                  style: TextStyle(fontSize: 12, color: Color(0xFFC6C6C8)),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: membersState.when(
                    data: (members) => members.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                '暂无参与者信息',
                                style: TextStyle(color: Color(0xFF8E8E93)),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: members.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFE5E5EA),
                            ),
                            itemBuilder: (_, index) =>
                                _buildMemberTile(members[index], myUserId),
                          ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    error: (_, __) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          '参与者列表仅相册成员可见',
                          style: TextStyle(color: Color(0xFF8E8E93)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMemberTile(AlbumMemberModel member, String? myUserId) {
    final isMe = myUserId != null && myUserId == member.userId;
    final shortId = member.userId.length <= 8
        ? member.userId
        : '${member.userId.substring(0, 8)}…';
    final joinedLocal = member.joinedAt.toLocal();
    final joinedText =
        '${joinedLocal.year}-${_twoDigits(joinedLocal.month)}-'
        '${_twoDigits(joinedLocal.day)} '
        '${_twoDigits(joinedLocal.hour)}:${_twoDigits(joinedLocal.minute)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFE5E5EA),
              shape: BoxShape.circle,
            ),
            child: Icon(
              member.isCreator ? Icons.star_rounded : Icons.person_rounded,
              size: 22,
              color: const Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '用户 $shortId${isMe ? '（我）' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '加入于 $joinedText',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: member.isCreator
                  ? const Color(0xFF1C1C1E)
                  : const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              member.isCreator ? '创建者' : '参与者',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: member.isCreator
                    ? Colors.white
                    : const Color(0xFF8E8E93),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final photosState = ref.watch(albumPhotosProvider(album.id));
    final uploadState = ref.watch(photoUploadProvider(album.id));
    final expiryState = ref.watch(albumExpiryProvider(album.id));
    final membersState = ref.watch(albumMembersProvider(album.id));
    final myUserId = ref.watch(authProvider).value?.user?.id;
    final effectiveExpiresAt =
        (expiryState.hasValue ? expiryState.value : null) ?? album.expiresAt;
    final isExpired = DateTime.now().toUtc().isAfter(effectiveExpiresAt);

    ref.listen<AsyncValue<DateTime?>>(albumExpiryProvider(album.id), (
      previous,
      next,
    ) {
      if (!next.hasValue) {
        return;
      }

      final latestExpiresAt = next.value;
      if (latestExpiresAt == null ||
          DateTime.now().toUtc().isAfter(latestExpiresAt)) {
        final photos =
            (ref.read(albumPhotosProvider(album.id)).hasValue
                ? ref.read(albumPhotosProvider(album.id)).value
                : null) ??
            [];
        PhotoCacheService.clearAlbum(photos);
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    });

    // 照片列表刷新时重置预加载计数
    ref.listen<AsyncValue<List<PhotoModel>>>(albumPhotosProvider(album.id), (
      previous,
      next,
    ) {
      if (next.hasValue) {
        _prefetchedCount = 0;
      }
    });

    // 上传结果提示：失败/成功都给出明确反馈，避免 Web 端错误被静默吞掉
    ref.listen<PhotoUploadState>(photoUploadProvider(album.id), (
      previous,
      next,
    ) {
      if (next.errorMessage != null) {
        showIosToast(context, next.errorMessage!, isError: true);
      } else if (next.successMessage != null) {
        showIosToast(context, next.successMessage!);
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── 主内容 ──
          Positioned.fill(
            child: photosState.when(
              data: (photos) {
                if (isExpired) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(80),
                            ),
                            child: const Icon(
                              Icons.schedule_send_outlined,
                              size: 36,
                              color: Color(0xFFFF3B30),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '该相册已过期',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFF3B30),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '正在返回首页...',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (photos.isEmpty && !uploadState.isUploading) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(80),
                            ),
                            child: const Icon(
                              Icons.image_outlined,
                              size: 32,
                              color: Color(0xFFC6C6C8),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '相册里空空如也',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '快点击下方按钮，分享第一张照片吧',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 88, bottom: 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 1,
                    mainAxisSpacing: 1,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];

                    return GestureDetector(
                      onTap: () async {
                        // 预热：在 Hero 动画播放期间后台下载 Preview
                        PhotoCacheService.previews.downloadFile(
                          PhotoImageService.getPreview(photo.fileUrl),
                        );

                        final int? updatedIndex = await Navigator.of(context)
                            .push<int>(
                              MaterialPageRoute(
                                builder: (context) => PhotoViewerPage(
                                  photos: photos,
                                  initialIndex: index,
                                  albumId: album.id,
                                  creatorId: album.creatorId,
                                ),
                              ),
                            );

                        if (updatedIndex != null &&
                            mounted &&
                            _scrollController.hasClients) {
                          final int row = updatedIndex ~/ 3;
                          final double targetOffset = row * 120.0;
                          final maxScroll =
                              _scrollController.position.maxScrollExtent;
                          final safeOffset = targetOffset.clamp(0.0, maxScroll);
                          _scrollController.animateTo(
                            safeOffset,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      child: Hero(
                        tag: 'photo_${photo.id}',
                        child: CachedNetworkImage(
                          imageUrl: PhotoImageService.getThumbnail(
                            photo.fileUrl,
                          ),
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: const Color(0xFFE5E5EA)),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFFF2F2F7),
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Color(0xFFC6C6C8),
                            ),
                          ),
                          cacheManager: PhotoCacheService.thumbnails,
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFFF3B30),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        error.toString().replaceAll('Exception: ', ''),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          ref
                              .read(albumPhotosProvider(album.id).notifier)
                              .refresh();
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Sticky Header ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 44, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              album.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  album.shareCode,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF8E8E93),
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const Text(
                                  ' · ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFC6C6C8),
                                  ),
                                ),
                                AlbumCountdownWidget(
                                  expiresAt: effectiveExpiresAt,
                                ),
                                const Text(
                                  ' · ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFC6C6C8),
                                  ),
                                ),
                                // 参与者入口：点击展开参与者列表
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () =>
                                      _showMembersSheet(membersState, myUserId),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.group_outlined,
                                          size: 12,
                                          color: Color(0xFF8E8E93),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          membersState.hasValue
                                              ? '${membersState.value!.length}'
                                              : '…',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF8E8E93),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 22),
                        onPressed: () {
                          ref
                              .read(albumPhotosProvider(album.id).notifier)
                              .refresh();
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E5EA)),
                ],
              ),
            ),
          ),

          // ── FAB ──
          Positioned(
            right: 16,
            bottom: 32,
            child: uploadState.isUploading
                ? Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            value: uploadState.progress,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '上传中 ${(uploadState.progress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  )
                : SizedBox(
                    width: 56,
                    height: 56,
                    child: FloatingActionButton(
                      onPressed: isExpired
                          ? null
                          : () => _handleUpload(context),
                      backgroundColor: const Color(0xFF1C1C1E),
                      shape: const CircleBorder(),
                      elevation: 8,
                      child: const Icon(
                        Icons.add,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
