import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/album_participation_provider.dart';
import '../providers/auth_provider.dart';
import '../services/guest_session_manager.dart';
import '../services/photo_cache_service.dart';
import '../services/photo_image_service.dart';
import '../widgets/ios_toast.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  // ── 问候语 ──
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '早上好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  String _subGreeting(AuthState state) {
    if (state.isNormalUser) return '继续记录属于你们的回忆。';
    return '输入好友分享码即可查看共享相册。';
  }

  // ── 右侧半屏菜单（苹果风格：磨砂遮罩 + 右滑入面板） ──
  void _openSideMenu(ThemeData theme, AsyncValue<AuthState> authState) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black.withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          const SizedBox.shrink(),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            // 遮罩层：点击关闭
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(dialogContext).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            // 右侧半屏面板
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: MediaQuery.of(dialogContext).size.width * 0.68,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: _buildSideMenuPanel(authState),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSideMenuPanel(AsyncValue<AuthState> authState) {
    final state = authState.value;
    final profile = state?.profile;
    final isNormal = state?.isNormalUser == true;
    final nickname = profile?.nickname ?? '游客';

    return SafeArea(
      child: Material(
        color: const Color(0xFFF2F2F7),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF2F2F7),
            borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // ── 身份头部 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isNormal
                            ? const Color(0xFF34C759).withValues(alpha: 0.12)
                            : const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(52),
                      ),
                      child: Icon(
                        isNormal
                            ? Icons.check_circle_rounded
                            : Icons.person_outline_rounded,
                        size: 26,
                        color: isNormal
                            ? const Color(0xFF34C759)
                            : const Color(0xFF8E8E93),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isNormal ? '正式账号' : '游客身份',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isNormal)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E5EA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '未升级',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── 功能列表（预留项：点击提示即将上线） ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '通用',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8E8E93).withValues(alpha: 0.8),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _buildMenuTile(
                      icon: Icons.person_outline_rounded,
                      title: '我的账户',
                      onTap: () => showIosToast(context, '该功能即将上线'),
                    ),
                    const Divider(height: 1, color: Color(0xFFE5E5EA)),
                    _buildMenuTile(
                      icon: Icons.cleaning_services_outlined,
                      title: '清理缓存',
                      onTap: () => showIosToast(context, '该功能即将上线'),
                    ),
                    const Divider(height: 1, color: Color(0xFFE5E5EA)),
                    _buildMenuTile(
                      icon: Icons.info_outline_rounded,
                      title: '关于',
                      onTap: () => showIosToast(context, '该功能即将上线'),
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // ── 底部主操作 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: () async {
                          if (isNormal) {
                            await ref.read(authProvider.notifier).signOut();
                            if (mounted) {
                              Navigator.of(context).pop(); // 关闭菜单
                              showIosToast(context, '已退出登录，已切换为游客模式');
                            }
                          } else {
                            Navigator.of(context).pop(); // 关闭菜单
                            Navigator.of(context).pushNamed('/login');
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1C1E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(isNormal ? '退出登录' : '升级身份'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF8E8E93)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFFC6C6C8),
            ),
          ],
        ),
      ),
    );
  }

  // ── 相册列表 ──
  Widget _buildAlbumList(
    ThemeData theme,
    AsyncValue<List<AlbumParticipationEntry>> albumsState,
  ) {
    return albumsState.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFFC6C6C8).withValues(alpha: 0.5),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(64),
                  ),
                  child: const Icon(
                    Icons.folder_outlined,
                    size: 28,
                    color: Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '还没有参与过任何相册',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '点击下方按钮创建或加入相册',
                  style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
                ),
              ],
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: List.generate(entries.length, (index) {
              final entry = entries[index];
              final album = entry.album;
              final isLast = index == entries.length - 1;

              return Column(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed('/album_detail', arguments: album),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // 封面缩略图：读取相册第一张照片的缩略图；无照片时回退图标
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: entry.coverPhotoUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: PhotoImageService.getThumbnail(
                                        entry.coverPhotoUrl!,
                                      ),
                                      fit: BoxFit.cover,
                                      cacheManager:
                                          PhotoCacheService.thumbnails,
                                      placeholder: (_, _) => Container(
                                        color: const Color(0xFFE5E5EA),
                                        child: const Icon(
                                          Icons.image_outlined,
                                          size: 24,
                                          color: Color(0xFF8E8E93),
                                        ),
                                      ),
                                      errorWidget: (_, _, _) => Container(
                                        color: const Color(0xFFF2F2F7),
                                        child: const Icon(
                                          Icons.broken_image_outlined,
                                          size: 24,
                                          color: Color(0xFFC6C6C8),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFFE5E5EA),
                                      child: const Icon(
                                        Icons.image_outlined,
                                        size: 24,
                                        color: Color(0xFF8E8E93),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  album.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1C1C1E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      album.shareCode,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF8E8E93),
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFC6C6C8),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      entry.isCreator ? '创建者' : '参与者',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: Color(0xFFC6C6C8),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isLast)
                    const Divider(
                      height: 1,
                      indent: 80,
                      color: Color(0xFFE5E5EA),
                    ),
                ],
              );
            }),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 20, color: Color(0xFFFF3B30)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '获取失败',
                style: const TextStyle(fontSize: 15, color: Color(0xFFFF3B30)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 创建入口 ──
  void _openCreateFlow(BuildContext context, AsyncValue<AuthState> authState) {
    final isNormal = authState.value?.isNormalUser ?? false;
    if (!isNormal) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('需要升级身份'),
          content: const Text('升级身份后，即可创建共享相册，并上传、下载和管理照片。'),
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
              child: const Text('升级身份'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed('/create');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final currentUser = authState.value?.user;
    final myAlbumsState = currentUser == null
        ? null
        : ref.watch(myAlbumsProvider(currentUser.id));

    final name =
        authState.value?.profile?.nickname ??
        GuestSessionManager.roleLabel(authState.value);
    final subGreeting = authState.value != null
        ? _subGreeting(authState.value!)
        : '';

    // 根路由拦截系统返回：避免 Android 浏览器 back 触发“无法退出”提示，
    // 以及 iOS Safari 边缘右滑在根页面触发浏览器历史回退导致的异常。
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        body: SafeArea(
          child: Stack(
            children: [
              // 可滚动主体
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 64, 24, 140),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Header：问候语 ──
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_greeting()}，',
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E),
                                height: 1.2,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E),
                                height: 1.2,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subGreeting,
                          style: const TextStyle(
                            fontSize: 17,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ── 我的相册标签 + 列表 ──
                        if (myAlbumsState != null) ...[
                          Row(
                            children: [
                              _sectionLabel('我的相册'),
                              const Spacer(),
                              myAlbumsState.whenOrNull(
                                    data: (entries) => Text(
                                      '${entries.length} 个',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF8E8E93),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ) ??
                                  const SizedBox.shrink(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildAlbumList(theme, myAlbumsState),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // ── 固定左上角菜单按钮（点击展开右侧半屏功能面板） ──
              Positioned(
                top: 8,
                left: 16,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openSideMenu(theme, authState),
                    child: Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.line_weight_rounded,
                        size: 24,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                ),
              ),

              // ── 底部固定操作栏 ──
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00F2F2F7), Color(0xFFF2F2F7)],
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: () =>
                                _openCreateFlow(context, authState),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1C1C1E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('创建相册'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pushNamed('/join');
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFFE5E5EA),
                              foregroundColor: const Color(0xFF1C1C1E),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('加入相册'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 节标签 ──
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E93),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
