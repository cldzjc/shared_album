import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/join_album_provider.dart';
import '../providers/album_participation_provider.dart';
import '../widgets/ios_toast.dart';

class JoinPage extends ConsumerStatefulWidget {
  const JoinPage({super.key});

  @override
  ConsumerState<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends ConsumerState<JoinPage> {
  final _formKey = GlobalKey<FormState>();
  final _shareCodeController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _shareCodeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final shareCode = _shareCodeController.text.trim();
    final password = _passwordController.text;

    try {
      // 执行校验逻辑，获取返回的 AlbumModel
      final album = await ref
          .read(joinAlbumProvider.notifier)
          .joinAlbum(shareCode, password);

      if (mounted) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null) {
          // 记录参与关系（创建者本人跳过，避免覆盖 creator 角色）
          if (album.creatorId != currentUserId) {
            try {
              await recordAlbumParticipation(
                albumId: album.id,
                userId: currentUserId,
                relationType: 'member',
              );
            } catch (_) {
              // 参与记录写入失败不阻断加入流程
            }
          }
          ref.invalidate(myAlbumsProvider(currentUserId));
        }
      }

      // async gap 后重新确认仍挂载，再使用 context
      if (!mounted) return;

      showIosToast(context, '成功加入相册');
      Navigator.of(
        context,
      ).pushReplacementNamed('/album_detail', arguments: album);
    } catch (e) {
      if (mounted) {
        showIosToast(
          context,
          e.toString().replaceAll('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final joinStatus = ref.watch(joinAlbumProvider);
    final isLoading = joinStatus.isLoading;

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
                          // ── 说明文字 ──
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '请输入好友分享的 6 位数字分享码，\n以及对应的访问密码',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                color: Color(0xFF8E8E93),
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // ── 输入卡片 ──
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                _buildInput(
                                  controller: _shareCodeController,
                                  hint: '分享码 (6位数字)',
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  maxLength: 6,
                                  textStyle: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF1C1C1E),
                                    letterSpacing: 8,
                                    fontFamily: 'monospace',
                                  ),
                                  enabled: !isLoading,
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) {
                                      return '请输入相册分享码';
                                    }
                                    if (val.trim().length != 6) {
                                      return '分享码必须为 6 位';
                                    }
                                    return null;
                                  },
                                ),
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFE5E5EA),
                                ),
                                _buildInput(
                                  controller: _passwordController,
                                  hint: '访问密码',
                                  textAlign: TextAlign.center,
                                  obscure: true,
                                  enabled: !isLoading,
                                  validator: (val) {
                                    if (val == null || val.isEmpty) {
                                      return '请输入相册密码';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
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
                        '加入相册',
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

            // ── 底部固定按钮 ──
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
                      child: Text(isLoading ? '验证中...' : '加入相册'),
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

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    TextAlign textAlign = TextAlign.start,
    bool obscure = false,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    TextStyle? textStyle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textAlign: textAlign,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      enabled: enabled,
      validator: validator,
      style:
          textStyle ?? const TextStyle(fontSize: 17, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 17),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        errorStyle: const TextStyle(fontSize: 12),
      ),
    );
  }
}
