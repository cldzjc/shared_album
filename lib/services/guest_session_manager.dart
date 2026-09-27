import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../providers/auth_provider.dart';

/// 身份等级（与 profiles.account_type 对齐）
enum IdentityLevel { guest, normal }

/// 业务动作枚举
enum IdentityAction {
  browseAlbum,
  joinAlbum,
  createAlbum,
  uploadPhoto,
  downloadPhoto,
  deleteResource,
}

/// 统一身份辅助层
///
/// 身份判断依据：profiles.account_type（由 AuthState.profile 携带）
/// 不再依赖 user == null，因为匿名用户也有合法 uid。
class GuestSessionManager {
  /// 从 AuthState 解析身份等级
  static IdentityLevel resolveLevelFromState(AuthState? authState) {
    if (authState?.profile?.isNormal == true) return IdentityLevel.normal;
    return IdentityLevel.guest;
  }

  /// 兼容旧调用点（只传 User）：仅凭 user 无法判断 account_type，
  /// 此处保守返回 guest，调用方应尽量迁移到 resolveLevelFromState。
  @Deprecated('请改用 resolveLevelFromState(authState)')
  static IdentityLevel resolveLevel(User? user) {
    return user == null ? IdentityLevel.guest : IdentityLevel.guest;
  }

  /// 权限判断：基于 AuthState 中的 account_type
  static bool canExecuteFromState(IdentityAction action, AuthState? authState) {
    switch (action) {
      case IdentityAction.browseAlbum:
      case IdentityAction.joinAlbum:
        return true; // 游客可浏览 / 加入
      case IdentityAction.createAlbum:
      case IdentityAction.uploadPhoto:
      case IdentityAction.downloadPhoto:
      case IdentityAction.deleteResource:
        return authState?.isNormalUser == true; // 必须是 normal 用户
    }
  }

  /// 兼容旧调用点（只传 User）：匿名用户有 uid 但不是 normal，保守返回 false。
  static bool canExecute(IdentityAction action, User? user) {
    switch (action) {
      case IdentityAction.browseAlbum:
      case IdentityAction.joinAlbum:
        return true;
      case IdentityAction.createAlbum:
      case IdentityAction.uploadPhoto:
      case IdentityAction.downloadPhoto:
      case IdentityAction.deleteResource:
        // 旧接口无法读 account_type，保守拦截（调用方应迁移到 canExecuteFromState）
        return false;
    }
  }

  /// 身份标签（用于 UI 展示）
  static String roleLabel(AuthState? authState) {
    return resolveLevelFromState(authState) == IdentityLevel.normal ? '正式用户' : '游客';
  }

  /// 账号类型标签
  static String accountLabel(AuthState? authState) {
    return resolveLevelFromState(authState) == IdentityLevel.normal ? 'Normal' : 'Guest';
  }

  /// 操作拒绝提示文案
  static String actionDeniedMessage(IdentityAction action) {
    switch (action) {
      case IdentityAction.createAlbum:
        return '创建相册需要正式账号，请先升级身份';
      case IdentityAction.uploadPhoto:
        return '上传照片需要正式账号，请先升级身份';
      case IdentityAction.downloadPhoto:
        return '下载照片需要正式账号，请先升级身份';
      case IdentityAction.deleteResource:
        return '删除资源需要正式账号，请先升级身份';
      case IdentityAction.browseAlbum:
      case IdentityAction.joinAlbum:
        return '该操作无需额外权限';
    }
  }
}
