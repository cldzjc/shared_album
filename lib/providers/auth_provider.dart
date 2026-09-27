// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 1. 用户资料数据模型（含 account_type）
class UserProfile {
  final String id;
  final String nickname;
  final String? avatarUrl;

  /// 'guest' 或 'normal'
  final String accountType;

  UserProfile({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.accountType = 'guest',
  });

  bool get isGuest => accountType == 'guest';
  bool get isNormal => accountType == 'normal';

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      nickname: map['nickname'] as String? ?? '游客',
      avatarUrl: map['avatar_url'] as String?,
      accountType: map['account_type'] as String? ?? 'guest',
    );
  }
}

/// 2. 鉴权状态封装
class AuthState {
  final User? user;
  final UserProfile? profile;

  AuthState({this.user, this.profile});

  /// 业务身份：只要有 profile 且 account_type='normal' 就是正式用户
  bool get isNormalUser => profile?.isNormal == true;

  /// 是否有合法 session（匿名/正式用户都算）
  bool get hasSession => user != null;
}

/// 3. 注册结果封装
class SignUpResult {
  final bool requiresEmailConfirmation;
  final String message;

  SignUpResult({
    required this.requiresEmailConfirmation,
    required this.message,
  });
}

/// 4. 全局 Auth 状态管理 Notifier（非 autoDispose，保证全局生命周期内状态不丢失）
class AuthNotifier extends AsyncNotifier<AuthState> {
  StreamSubscription<dynamic>? _authSubscription;

  /// 防止同一 UID 并发执行 ensureProfile，消除 build() 与 Listener 的竞态
  final Set<String> _ensuringProfiles = {};

  Never _rethrowAsyncError(AsyncError<AuthState> asyncError) {
    final error = asyncError.error;
    if (error is Exception) throw error;
    throw Exception(error.toString());
  }

  @override
  Future<AuthState> build() async {
    final client = Supabase.instance.client;

    // 确保旧订阅先被取消，防止重复订阅
    _authSubscription?.cancel();

    // 订阅 Supabase 鉴权状态变化，自动刷新 Riverpod 状态
    _authSubscription = client.auth.onAuthStateChange.listen((data) async {
      final user = data.session?.user;
      final event = data.event;
      print("[Auth Listener] 收到事件: $event");

      if (user != null) {
        // 如果当前状态已是该用户并且 profile 存在，则不重复处理，避免竞态
        final currentState = state.value;
        if (currentState?.user?.id == user.id &&
            currentState?.profile != null) {
          print("[Auth Listener] 状态已存在且匹配，忽略重复处理");
          return;
        }

        final profile = await _fetchProfile(user.id);
        if (profile != null) {
          state = AsyncData(AuthState(user: user, profile: profile));
        } else {
          // 仅在当前不是 loading 状态时由 listener 补齐（以防与 build 阶段冲突）
          if (state.isLoading == false) {
            print("[Auth Listener] Profile 缺失，开始 ensureProfile");
            final ensured = await _ensureProfile(user);
            state = AsyncData(AuthState(user: user, profile: ensured));
          }
        }
      } else {
        // 当 session 变为 null 且当前不处于加载状态时，重新触发 invalidateSelf 从而安全重建
        if (state.value?.user != null && state.isLoading == false) {
          print("[Auth Listener] Session 被清空，触发 invalidateSelf 重建");
          state = AsyncData(AuthState(user: null, profile: null));
          ref.invalidateSelf();
        }
      }
    });

    ref.onDispose(() => _authSubscription?.cancel());

    print("[Auth] 开始初始化...");

    // 1. 检查 Session
    final currentSession = client.auth.currentSession;
    User? currentUser = client.auth.currentUser;
    print("[Auth] 检查 Session...");

    if (currentUser != null) {
      print("[Auth] 已有本地 Session");
      try {
        // 向服务器验证 session 是否真的有效（防止后台删除了用户但本地缓存仍在）
        final response = await client.auth.getUser();
        currentUser = response.user;
        print("[Auth] Session 服务器校验成功");
      } catch (e) {
        print("[Auth] Session 服务器校验失败，尝试恢复");
        try {
          await client.auth.refreshSession();
          currentUser = client.auth.currentUser;
          print("[Auth] refreshSession 成功");
        } catch (refreshError) {
          print(
            "[Auth] refreshSession 也失败 | error: $refreshError | 清除无效本地 Session",
          );
          try {
            await client.auth.signOut();
          } catch (_) {}
          currentUser = null;
        }
      }
    }

    // 2. 没有 Session 时，调用 signInAnonymously()
    if (currentUser == null) {
      print("[Auth] 没有 Session，准备调用 signInAnonymously()...");
      try {
        final response = await client.auth.signInAnonymously();
        currentUser = response.user;
        final newSession = response.session;
        print("[Auth] signInAnonymously() 调用成功");

        if (currentUser == null) {
          throw Exception("signInAnonymously 成功但 currentUser 为 null");
        }
      } catch (e) {
        print("[Auth] signInAnonymously() 失败 | error: $e");
        throw Exception("匿名登录失败: $e");
      }
    }

    // 3. 确认 currentUser != null
    final user = currentUser;

    // 4. 获取 auth.uid() 并 upsert profiles
    final uid = user.id;
    // 检查是否已有 profile
    UserProfile? profile = await _fetchProfile(uid);
    if (profile == null) {
      print("[Auth] Profile 不存在，开始 ensureProfile");
      profile = await _ensureProfile(user);
      if (profile == null) {
        throw Exception("upsert profiles 失败");
      }
    } else {
      print(
        "[Auth] Profile 已存在: ${profile.nickname}, accountType: ${profile.accountType}",
      );
    }

    // 5. 完成初始化
    print("[Auth] 初始化完成！");
    return AuthState(user: user, profile: profile);
  }

  // ─────────────────────────── 内部方法 ───────────────────────────

  /// 从 profiles 表获取用户资料（含 account_type）
  Future<UserProfile?> _fetchProfile(String userId) async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (response != null) return UserProfile.fromMap(response);
    } catch (_) {
      // 捕获连接失败等异常，防止主流程崩溃
    }
    return null;
  }

  /// 若 profiles 里还没有资料，则写入一条（guest 默认）
  /// 同一 UID 生命周期内只允许一个 ensureProfile 在执行，消除 build() / Listener 竞态
  Future<UserProfile?> _ensureProfile(
    User user, {
    String? nicknameHint,
    String accountType = 'guest',
  }) async {
    final uid = user.id;
    if (_ensuringProfiles.contains(uid)) {
      print("[Auth] ensureProfile 已在执行中，跳过重复调用");
      return _fetchProfile(uid);
    }
    _ensuringProfiles.add(uid);
    try {
      print("[Auth] ensureProfile 开始");
      final client = Supabase.instance.client;
      final nickname = _resolveNickname(user, nicknameHint: nicknameHint);

      await client
          .from('profiles')
          .upsert(
            {
              'id': uid,
              'nickname': nickname,
              'account_type': accountType,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'id',
            ignoreDuplicates: false,
          );

      final profile = UserProfile(
        id: uid,
        nickname: nickname,
        accountType: accountType,
      );
      print("[Auth] ensureProfile 完成 | Profile: ${profile.nickname}");
      return profile;
    } catch (e) {
      print("[Auth] ensureProfile 失败 | error: $e");
      return null;
    } finally {
      _ensuringProfiles.remove(uid);
    }
  }

  String _resolveNickname(User user, {String? nicknameHint}) {
    final metadataNickname = user.userMetadata?['nickname'] as String?;
    final fallbackEmail = user.email ?? '';
    final fallbackLocalPart = fallbackEmail.contains('@')
        ? fallbackEmail.split('@').first
        : '游客';

    final resolved = (nicknameHint?.trim().isNotEmpty == true)
        ? nicknameHint!.trim()
        : (metadataNickname?.trim().isNotEmpty == true)
        ? metadataNickname!.trim()
        : fallbackLocalPart;

    return resolved.isEmpty ? '游客' : resolved;
  }

  // ─────────────────────────── 公开方法 ───────────────────────────

  /// 【身份升级】游客绑定邮箱密码 → 升级为 normal 用户
  /// 使用 Supabase updateUser，uid 保持不变
  Future<SignUpResult> upgradeWithEmail(
    String email,
    String password,
    String nickname,
  ) async {
    state = const AsyncValue.loading();
    final nextState = await AsyncValue.guard(() async {
      final client = Supabase.instance.client;
      final currentUser = client.auth.currentUser;
      if (currentUser == null) {
        throw Exception('无法升级：当前没有有效 session，请重启 App');
      }

      // 用 updateUser 绑定邮箱密码，uid 保持不变（Supabase Anonymous Auth 官方升级路径）
      // 手机网络不稳定时请求可能长时间挂起，加超时保证按钮状态能恢复。
      await client.auth
          .updateUser(
            UserAttributes(
              email: email,
              password: password,
              data: {'nickname': nickname.trim()},
            ),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('网络连接超时，请检查网络后重试'),
          );

      // 更新 profiles：account_type 改为 normal，nickname 写入
      await client
          .from('profiles')
          .update({
            'nickname': nickname.trim(),
            'account_type': 'normal',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', currentUser.id)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('网络连接超时，请检查网络后重试'),
          );

      final profile =
          await _fetchProfile(currentUser.id) ??
          UserProfile(
            id: currentUser.id,
            nickname: nickname.trim(),
            accountType: 'normal',
          );
      return AuthState(user: currentUser, profile: profile);
    });

    state = nextState;
    if (nextState is AsyncError<AuthState>) _rethrowAsyncError(nextState);

    // Supabase 会发送验证邮件，邮件确认后 account_type 才生效可以根据业务决定是否等待确认
    // 这里乐观更新，告知用户需要确认邮箱
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser?.email == null) {
      return SignUpResult(
        requiresEmailConfirmation: true,
        message: '绑定邮件已发送，请在邮箱中点击确认链接完成升级。确认后即可用邮箱密码重新登录。',
      );
    }
    return SignUpResult(
      requiresEmailConfirmation: false,
      message: '账号升级成功！您现在是正式用户。',
    );
  }

  /// 【正式登录】已有 normal 账号的用户登录（uid 与匿名 uid 不同，需注意）
  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    final nextState = await AsyncValue.guard(() async {
      final client = Supabase.instance.client;

      final response = await client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('网络连接超时，请检查网络后重试'),
          );

      final user = response.user;
      if (user == null) throw Exception('登录失败，用户为空');

      final profile =
          await _fetchProfile(user.id) ??
          await _ensureProfile(user, accountType: 'normal');
      return AuthState(user: user, profile: profile);
    });

    state = nextState;
    if (nextState is AsyncError<AuthState>) _rethrowAsyncError(nextState);
  }

  /// 退出登录：退出后自动重新创建匿名 session
  Future<void> signOut() async {
    state = const AsyncValue.loading();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // 忽略退出错误
    }
    // 退出后重新匿名登录：直接 invalidateSelf 让 build 重新构建即可
    ref.invalidateSelf();
  }
}

/// 5. 暴露全局 authProvider（keepAlive，不 autoDispose，保证 Auth 状态全程存活）
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
