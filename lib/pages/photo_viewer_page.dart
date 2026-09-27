import 'dart:ui' as ui;
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/album_photos_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/photo_download_provider.dart';
import '../services/guest_session_manager.dart';
import '../services/photo_cache_service.dart';
import '../services/photo_delete_service.dart';
import '../services/photo_image_service.dart';
import '../widgets/ios_toast.dart';

class PhotoViewerPage extends ConsumerStatefulWidget {
  final List<PhotoModel> photos;
  final int initialIndex;
  final String albumId;
  final String creatorId;

  const PhotoViewerPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.albumId,
    required this.creatorId,
  });

  @override
  ConsumerState<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends ConsumerState<PhotoViewerPage>
    with TickerProviderStateMixin {
  late int _currentIndex;
  late List<PhotoModel> _photos;
  final PhotoDeleteService _deleteService = PhotoDeleteService();

  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _photos = List.from(widget.photos);
    _preloadAdjacent(_currentIndex);
    PhotoImageService.debugImageInfo(widget.photos[_currentIndex].fileUrl);
  }

  void _preloadAdjacent(int index) {
    for (final offset in [-1, 1]) {
      final idx = index + offset;
      if (idx >= 0 && idx < _photos.length) {
        try {
          PhotoCacheService.previews.downloadFile(
            PhotoImageService.getPreview(_photos[idx].fileUrl),
          );
        } catch (_) {}
      }
    }
  }

  bool _canDelete(PhotoModel photo) {
    final currentUser = ref.read(authProvider).value?.user;
    if (currentUser == null) return false;
    return photo.uploaderId == currentUser.id ||
        widget.creatorId == currentUser.id;
  }

  // ── 像素级还原苹果的双击放大动画 ──
  // 1. 修复双击回调函数签名：去掉多余的 TapDownDetails，只保留 state
  void _onDoubleTap(ExtendedImageGestureState state) {
    final details = state.gestureDetails;
    if (details == null) return;

    // 获取当前缩放值
    final currentScale = details.totalScale ?? 1.0;
    // 如果已经是放大状态则回弹至 1.0x，否则放大至 2.5x
    final targetScale = currentScale > 1.0 ? 1.0 : 2.5;

    // 创建一次性动画控制器，像素级对齐 iOS 的 250ms 曲线
    final animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    final animation = Tween<double>(begin: currentScale, end: targetScale)
        .animate(
          CurvedAnimation(
            parent: animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    // 在动画每一帧强制刷新手势矩阵，达成丝滑过渡
    animation.addListener(() {
      state.handleDoubleTap(
        scale: animation.value,
        doubleTapPosition: state.pointerDownPosition,
      );
    });

    animationController.forward().then((_) => animationController.dispose());
  }

  Future<void> _deletePhoto(PhotoModel photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除照片'),
        content: const Text('该操作无法撤销，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // ── Optimistic UI：立即从本地列表移除并切换 ──
    final deletedPhoto = photo;
    final deletedIndex = _currentIndex;

    setState(() {
      _photos.removeWhere((p) => p.id == photo.id);
      if (_photos.isEmpty) {
        // 最后一张：关闭查看器
        Navigator.of(context).pop();
      } else if (_currentIndex >= _photos.length) {
        _currentIndex = _photos.length - 1;
      }
    });

    // ── 后台异步删除 ──
    try {
      await _deleteService.deletePhoto(photoId: deletedPhoto.id);
      await PhotoCacheService.clearPhoto(deletedPhoto);
      if (mounted) {
        ref.read(albumPhotosProvider(widget.albumId).notifier).refresh();
      }
    } catch (_) {
      // 服务器删除失败：恢复照片
      if (mounted) {
        setState(() {
          _photos.insert(deletedIndex.clamp(0, _photos.length), deletedPhoto);
          _currentIndex = deletedIndex.clamp(0, _photos.length - 1);
        });
        showIosToast(context, '删除失败，请重试', isError: true);
      }
    }
  }

  void _handleSave(PhotoModel photo) {
    final authState = ref.read(authProvider).value;
    if (!GuestSessionManager.canExecuteFromState(
      IdentityAction.downloadPhoto,
      authState,
    )) {
      showIosToast(context, '保存照片需要升级身份', isError: true);
      return;
    }
    final fileName = photo.storagePath.split('/').last;
    ref
        .read(photoDownloadProvider((photo.fileUrl, fileName)).notifier)
        .downloadPhoto();
    showIosToast(context, '开始保存照片到相册');
  }

  Widget _buildCircularButton({
    required IconData icon,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? Colors.white, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_photos.isEmpty) return const SizedBox.shrink();
    final currentPhoto = _photos[_currentIndex];
    final canDeleteCurrent = _canDelete(currentPhoto);

    // 下载结果提示：失败/成功都给出明确反馈
    final currentFileName = currentPhoto.storagePath.split('/').last;
    ref.listen(photoDownloadProvider((currentPhoto.fileUrl, currentFileName)), (
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
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 背景动态毛玻璃（淡入淡出切换）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: ImageFiltered(
              key: ValueKey('bg_${currentPhoto.id}'),
              imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: ExtendedNetworkImageProvider(
                      PhotoImageService.getPreview(currentPhoto.fileUrl),
                      cache: true,
                    ),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.4),
                      BlendMode.darken,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. 核心手势浏览层（已修正 Hero 动画和双击参数）
          ExtendedImageGesturePageView.builder(
            itemCount: _photos.length,
            controller: ExtendedPageController(initialPage: _currentIndex),
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              _preloadAdjacent(index);
            },
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final isCurrent = index == _currentIndex;
              return GestureDetector(
                onTap: () => setState(() => _showUI = !_showUI),
                child: HeroMode(
                  enabled: isCurrent,
                  child: Hero(
                    tag: 'photo_${photo.id}',
                    child: ExtendedImage.network(
                      PhotoImageService.getPreview(photo.fileUrl),
                      fit: BoxFit.contain,
                      mode: ExtendedImageMode.gesture,
                      cache: true,
                      initGestureConfigHandler: (state) {
                        return GestureConfig(
                          minScale: 1.0,
                          animationMinScale: 0.7,
                          maxScale: 4.0,
                          animationMaxScale: 4.5,
                          speed: 1.0,
                          inertialSpeed: 100.0,
                          initialScale: 1.0,
                          inPageView: true,
                        );
                      },
                      onDoubleTap: _onDoubleTap,
                    ),
                  ),
                ),
              );
            },
          ),

          // 3. 全局固定不动的顶层 UI
          if (_showUI) ...[
            // 左上角返回与页码指示器（形如：< 1/3）
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(_currentIndex),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_currentIndex + 1} / ${_photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 右上角删除按钮（位置和左上角完美对称）
            if (canDeleteCurrent)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 16,
                child: _buildCircularButton(
                  icon: Icons.delete_outline_rounded,
                  color: const Color(0xFFFF453A),
                  onTap: () => _deletePhoto(currentPhoto),
                ),
              ),

            // 右下角保存按钮
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              right: 16,
              child: _buildCircularButton(
                icon: Icons.download_rounded,
                onTap: () => _handleSave(currentPhoto),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
