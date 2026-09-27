import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../widgets/ios_toast.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();

  /// true = 新用户升级（从游客绑定邮箱）/ false = 已有账号直接登录
  bool _isUpgrade = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final nickname = _nicknameController.text.trim();

    final authNotifier = ref.read(authProvider.notifier);

    try {
      if (_isUpgrade) {
        final result = await authNotifier.upgradeWithEmail(
          email,
          password,
          nickname,
        );
        if (mounted) {
          showIosToast(context, result.message);
          if (!result.requiresEmailConfirmation) {
            Navigator.of(context).pop();
          }
        }
      } else {
        await authNotifier.signIn(email, password);
        if (mounted) {
          showIosToast(context, '登录成功，欢迎回来');
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceAll('Exception: ', '');
        final String friendly;
        if (message.contains('over_email_send_rate_limit') ||
            message.contains('email rate limit exceeded')) {
          friendly = '验证邮件发送太频繁，请稍后再试，或先去邮箱查看最新确认邮件';
        } else if (message.contains('ClientLoad') ||
            message.contains('SocketException') ||
            message.contains('ClientException') ||
            message.contains('超时')) {
          friendly = '网络连接失败，请检查网络后重试';
        } else {
          friendly = '操作失败: $message';
        }
        showIosToast(context, friendly, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;
    final isAlreadyNormal = authState.value?.isNormalUser == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Stack(
          children: [
            // ── 可滚动内容 ──
            Positioned.fill(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 140),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 顶部图标
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(
                            _isUpgrade
                                ? Icons.person_outline_rounded
                                : Icons.lock_outline_rounded,
                            size: 36,
                            color: const Color(0xFF1C1C1E),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 标题
                        Text(
                          _isUpgrade ? '升级身份' : '登录',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 副标题
                        Text(
                          _isUpgrade
                              ? '升级身份后，即可创建共享相册，\n并上传、下载和管理照片。'
                              : '欢迎回来！登录后即可\n继续使用共享相册。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            color: Color(0xFF8E8E93),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 40),

                        // ── 输入卡片（所有输入框合一） ──
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              if (_isUpgrade) ...[
                                _buildInput(
                                  controller: _nicknameController,
                                  hint: '昵称',
                                  enabled: !isLoading,
                                  validator: (val) {
                                    if (_isUpgrade &&
                                        (val == null || val.trim().isEmpty)) {
                                      return '请设置您的昵称';
                                    }
                                    return null;
                                  },
                                ),
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFE5E5EA),
                                ),
                              ],
                              _buildInput(
                                controller: _emailController,
                                hint: '邮箱地址',
                                keyboardType: TextInputType.emailAddress,
                                enabled: !isLoading,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return '请输入电子邮箱';
                                  }
                                  if (!_isValidEmail(val.trim())) {
                                    return '请输入正确的邮箱格式';
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
                                hint: '密码',
                                obscure: true,
                                enabled: !isLoading,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return '请输入密码';
                                  }
                                  if (val.length < 6) {
                                    return '密码长度不能少于 6 位';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),

                        // ── 切换按钮 ──
                        if (!isAlreadyNormal)
                          GestureDetector(
                            onTap: isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _isUpgrade = !_isUpgrade;
                                    });
                                  },
                            child: Text(
                              _isUpgrade ? '已有账号？直接登录' : '新用户？绑定邮箱升级身份',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 顶部取消按钮 ──
            Positioned(
              left: 8,
              top: 0,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  '取消',
                  style: TextStyle(fontSize: 17, color: Color(0xFF1C1C1E)),
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
                      child: Text(
                        isLoading
                            ? (_isUpgrade ? '升级中...' : '登录中...')
                            : (_isUpgrade ? '升级身份' : '登录'),
                      ),
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
    bool obscure = false,
    bool enabled = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      enabled: enabled,
      validator: validator,
      style: const TextStyle(fontSize: 17, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 17),
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
