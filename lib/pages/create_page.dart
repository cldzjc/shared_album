import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/album_participation_provider.dart';
import '../providers/create_album_provider.dart';
import '../services/guest_session_manager.dart';
import '../widgets/ios_toast.dart';

class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key});

  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _nicknamePrefilled = false;

  late final String _generatedShareCode;

  @override
  void initState() {
    super.initState();
    _generatedShareCode = _generateRandomShareCode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  String _generateRandomShareCode() {
    const chars = '0123456789';
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;

    final formPayload = CreateAlbumForm(
      name: _nameController.text,
      password: _passwordController.text,
      nickname: _nicknameController.text,
      shareCode: _generatedShareCode,
    );

    // 唤醒 Riverpod 状态机，开始异步入库逻辑
    ref.read(createAlbumProvider.notifier).submitAlbum(formPayload);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 通过 authProvider 读取登录状态，保持全局状态源屠一致
    final authState = ref.watch(authProvider);
    final currentNickname = authState.value?.profile?.nickname;
    final canCreateAlbum = GuestSessionManager.canExecuteFromState(
      IdentityAction.createAlbum,
      authState.value,
    );

    if (_nicknameController.text.isEmpty &&
        !_nicknamePrefilled &&
        currentNickname != null &&
        currentNickname.trim().isNotEmpty) {
      _nicknameController.text = currentNickname.trim();
      _nicknameController.selection = TextSelection.collapsed(
        offset: _nicknameController.text.length,
      );
      _nicknamePrefilled = true;
    }

    // 如果未登录，展示拦截提示界面，符合 MVP 规则
    if (!canCreateAlbum) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        size: 40,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '需要升级身份',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '升级身份后，即可创建共享相册，\n并上传、下载和管理照片。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        color: Color(0xFF8E8E93),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pushReplacementNamed('/login'),
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
                        child: const Text('升级身份'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
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
                        child: const Text('返回'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 订阅 Riverpod 的异步状态
    final createStatus = ref.watch(createAlbumProvider);
    final isLoading = createStatus.isLoading;

    // 🔴 顶层状态监听器：苹果风格处理“成功”与“失败”的反馈
    ref.listen<AsyncValue<String?>>(createAlbumProvider, (previous, next) {
      next.whenOrNull(
        data: (shareCode) {
          if (shareCode != null) {
            final currentUserId = ref.read(authProvider).value?.user?.id;
            if (currentUserId != null) {
              ref.invalidate(myAlbumsProvider(currentUserId));
            }

            // 苹果风格：创建页内弹出居中圆角弹窗，确认后再返回主页
            _showCreateSuccessDialog(shareCode);
          }
        },
        error: (error, _) {
          showIosToast(context, '创建失败: $error', isError: true);
        },
      );
    });

    // 键盘弹出时隐藏底部固定按钮（键盘避让的一部分，避免遮挡输入框）
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 60, 24, 140),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── 分享码卡片 ──
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  '专属分享码',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF8E8E93),
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _generatedShareCode,
                                  style: const TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1C1C1E),
                                    letterSpacing: 6,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── 输入卡片（左右填词型：标签在左，输入框在右） ──
                          Column(
                            children: [
                              _buildFieldCard(
                                label: '创建者昵称',
                                controller: _nicknameController,
                                hint: '例如：小明',
                                enabled: !isLoading,
                                validator: (val) =>
                                    (val == null || val.trim().isEmpty)
                                    ? '请输入昵称'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              _buildFieldCard(
                                label: '相册名称',
                                controller: _nameController,
                                hint: '给你的相册起个名字',
                                enabled: !isLoading,
                                validator: (val) =>
                                    (val == null || val.trim().isEmpty)
                                    ? '相册名称不能为空'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              _buildFieldCard(
                                label: '访问密码',
                                controller: _passwordController,
                                hint: '设置访问密码',
                                obscure: true,
                                enabled: !isLoading,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return '请设置相册访问密码';
                                  }
                                  if (val.length < 4) {
                                    return '密码太短，不能少于 4 位';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── 24h 提示 ──
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule_outlined,
                                size: 20,
                                color: Color(0xFF8E8E93),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  '相册将在创建 24 小时后自动销毁。\n到期后所有数据将被清除。',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF8E8E93),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── 顶部取消 + 标题 ──
            Positioned(
              left: 8,
              top: 0,
              right: 8,
              child: SizedBox(
                height: 44,
                child: Stack(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 17,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                    const Center(
                      child: Text(
                        '创建相册',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // -- bottom button: hidden when keyboard shows --
            if (!keyboardVisible)
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
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: isLoading ? null : _submitForm,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1C1E),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(
                            0xFF1C1C1E,
                          ).withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(isLoading ? '创建中...' : '确认创建'),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 单个表单字段卡片：左右填词型（标签在左，输入框在右）。
  /// [scrollPadding] 用于键盘避让：聚焦时框架会自动滚动，
  /// 让输入框紧邻键盘上方而不是被遮挡。
  Widget _buildFieldCard({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E),
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              obscureText: obscure,
              enabled: enabled,
              validator: validator,
              scrollPadding: const EdgeInsets.only(bottom: 240),
              style: const TextStyle(fontSize: 17, color: Color(0xFF1C1C1E)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFFC6C6C8),
                  fontSize: 17,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                errorStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 苹果风格创建成功弹窗：居中圆角、展示分享码，确认后返回主页
  void _showCreateSuccessDialog(String shareCode) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF2F2F7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          title: const Center(
            child: Text(
              '相册创建成功',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Text(
                '把这个分享码发给好友，即可加入相册',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
              ),
              const SizedBox(height: 20),
              Text(
                shareCode,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E),
                  letterSpacing: 6,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  if (mounted) {
                    Navigator.of(context).pop(); // 返回主页
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('好'),
              ),
            ),
          ],
        );
      },
    );
  }
}
