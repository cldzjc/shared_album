class AppConfig {
  static const String supabaseUrl = 'https://gahlsdtzrkrqdvbmftsd.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_H5lhlmvEEo61Wc39BeEz0A_cRxAUg3C';

  /// 免费版相册照片数量上限（当前 200 张，后期可调整）。
  ///
  /// 调整标准：按“上传 n 张照片”的阿里云 OSS 成本估算——
  /// 成本 ≈ 原图总大小(GB) × 存储单价(元/GB/月) + 浏览/下载流量(GB) × 外网下行流量单价(元/GB)。
  /// 单张原图按压缩后约 3-5MB、缩略图约 15-30KB 估算。
  ///
  /// 界面不直接展示上限数字，仅在用户上传达到上限时提示。
  /// ⚠️ 后端 Edge Function `oss-sign-upload` 中同步使用了 200 张的硬校验，
  /// 调整本常量时需同步修改后端，避免前后端上限不一致。
  static const int maxPhotosPerFreeAlbum = 200;
}
