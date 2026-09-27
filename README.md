# Shared Album 共享相册

一个基于 **Flutter + Supabase + 阿里云 OSS** 的临时共享相册应用。

创建者生成一个有效期 24 小时的相册，通过 **6 位数字分享码 + 访问密码** 分享给好友。好友**无需登录**即可浏览照片；正式账号用户可以上传、下载和管理照片。相册到期后由后端任务自动销毁云端资源。

解决的核心问题：聚会、活动等场景下，让一群人快速集中共享照片，且分享者无需注册账号、相册到期后云端数据自动消失。

## 核心功能

- **邮箱注册 / 登录**（Supabase Auth）
- **游客访问**：无需登录，凭分享码 + 密码即可加入并浏览相册
- **创建相册**：自动生成 6 位数字分享码、访问密码（客户端 SHA-256 哈希后入库）、24 小时自动过期
- **照片上传**：多图选择、上传进度、OSS 直传；免费版每册上限 200 张（前后端同步校验）
- **照片浏览**：缩略图网格流、全屏预览（手势缩放）、缩略图 / 预览 / 原图三级 URL
- **照片下载**：流式下载 + 进度回调 + 保存到系统相册（gal）
- **照片删除**：权限校验 + 二次确认；先删 OSS 原图，成功后再删数据库记录
- **过期自动清理**：Edge Function + Supabase Cron 后台批量清理过期相册（OSS 原图 + 数据库记录）
- **客户端缓存**：缩略图与预览双层磁盘缓存（`flutter_cache_manager`，LRU 淘汰）
- **Web 适配**：XHR 上传进度、Blob 下载

## 技术栈

| 层次 | 技术 |
| --- | --- |
| 客户端 | Flutter (Dart, Material 3)、Riverpod 3.x（手动声明模式，无代码生成） |
| 身份认证 | Supabase Auth（邮箱 + 密码） |
| 数据层 | Supabase PostgreSQL + PostgREST + Row Level Security |
| 服务端逻辑 | Supabase Edge Functions（Deno + TypeScript） |
| 对象存储 | 阿里云 OSS（预签名直传 + 图片样式缩略图） |
| 关键依赖 | `supabase_flutter`、`http`、`crypto`、`image_picker`、`cached_network_image`、`extended_image`、`gal`、`path_provider`、`connectivity_plus` |

## 项目架构

```
Flutter 客户端（lib/）
 ├─ pages/        页面与交互（ConsumerWidget / ConsumerStatefulWidget）
 ├─ providers/    Riverpod 状态层（AsyncNotifier 手动声明）
 ├─ services/     服务层（Supabase 初始化、图片 URL、缓存、上传/下载/删除）
 ├─ widgets/      通用组件（倒计时、Toast 等）
 └─ config/       全局静态配置
        │  PostgREST（anon key，受 RLS 约束）
        ▼
Supabase
 ├─ Auth              邮箱登录、身份校验
 ├─ PostgreSQL        相册 / 照片 / 用户资料 / 参与关系元数据
 ├─ RLS               行级权限策略（创建者 / 参与者 / 游客边界）
 └─ Edge Functions    oss-sign-upload / delete-resource / cleanup-expired-albums
        │  （OSS AccessKey 仅存在于 Edge Function 环境变量）
        ▼
阿里云 OSS
 ├─ 原图存储（预签名 PUT 直传）
 └─ 样式缩略图（small-photos / preview）
```

职责边界：

- 客户端**不持有** OSS AccessKey，上传地址由 Edge Function 动态签名；
- `service_role` key 只存在于 Edge Function 环境变量中，数据库写操作均受 RLS 与函数内鉴权双重约束；
- 图片 URL 变换集中在 `lib/services/photo_image_service.dart`，更换存储服务只需改这一个文件。

## 关键技术实现

### 1. OSS 预签名直传（不经过 Supabase 服务器）

上传时客户端先调用 `oss-sign-upload` 获取预签名 PUT URL（60 秒有效），再用 `HTTP PUT` 将图片二进制直传 OSS，最后把 `publicUrl` 与 `objectKey` 写入 `photos` 表。上传流量不经过 Supabase 服务器，且客户端全程接触不到 OSS 密钥。

### 2. RLS 权限模型

`albums` / `photos` / `profiles` / `album_participants` 四张表均启用 RLS：相册参与者可浏览、创建者可管理、游客仅能通过"分享码 + 密码"校验流程访问脱敏数据。`password_hash` 等敏感字段不会被前端整行读取（建表与策略 SQL 见 `AGENTS.md`）。

### 3. 三级图片资源与双层缓存

每张照片有缩略图、预览、原图三种资源形态：浏览网格永远优先加载 OSS 样式缩略图（大幅降低流量成本）；全屏预览按需拉取；原图仅用于下载与保存。缓存层分"缩略图长期缓存"和"预览 LRU 缓存"，由 `flutter_cache_manager` 管理淘汰。

### 4. 一致性删除

`delete-resource` 与 `cleanup-expired-albums` 共享同一套删除方法：先删 OSS 原图，成功后才删数据库记录，避免"云上有图、库里无记录"或反向的不一致状态。

### 5. 过期相册后台清理

相册创建时写入 `expires_at = created_at + 24h`；客户端用独立倒计时组件做局部刷新；Supabase Cron 每 5 分钟触发一次 `cleanup-expired-albums`，单次批量处理 20 个过期相册并返回清理统计，不依赖客户端在线。

### 6. 游客机制

不依赖匿名登录。身份等级（guest / normal）由 `profiles.account_type` 判定，权限判断集中在 `lib/services/guest_session_manager.dart`：游客可浏览、加入；创建、上传、下载、删除均需正式账号，由 UI 层统一拦截引导登录。

## 项目目录

```
lib/
  config/    全局静态配置（Supabase 连接信息、业务常量）
  services/  服务层：Supabase 客户端、图片 URL/缓存、上传/下载/删除、游客权限
  providers/ Riverpod 状态层：认证、创建/加入相册、照片流、上传/下载状态
  pages/     页面：主页、创建、加入、登录、相册详情、全屏预览
  widgets/   通用组件：倒计时、iOS 风格 Toast
supabase/
  *.ts       Edge Functions：oss-sign-upload / delete-resource / cleanup-expired-albums
  *.sql      数据库视图与校验函数脚本
android/ ios/ web/ linux/ macos/ windows/  各平台工程目录
test/        widget 测试
```

## 本地运行

```bash
flutter pub get
flutter run
```

完整跑通业务需要自备以下云端资源（**请勿把真实密钥提交到仓库**）：

1. **Supabase 项目**：把 `lib/config/app_config.dart` 中的 `supabaseUrl`、`supabaseAnonKey` 替换为你的项目值。
2. **数据库**：按 `AGENTS.md` 中的建表与 RLS SQL 基线初始化表结构（参考 `supabase/*.sql`）。
3. **Edge Functions**：部署 `supabase/` 下的 4 个函数，并配置环境变量：

   ```text
   SUPABASE_URL
   SUPABASE_ANON_KEY
   SUPABASE_SERVICE_ROLE_KEY
   OSS_ACCESS_KEY_ID
   OSS_ACCESS_KEY_SECRET
   OSS_BUCKET
   OSS_REGION
   ```

4. **阿里云 OSS**：创建 Bucket，并在 OSS 控制台配置图片样式 `small-photos`、`preview`。
5. **定时任务**：在 Supabase Dashboard 配置 Cron，每 5 分钟调用一次 `cleanup-expired-albums`。

## 当前状态

- 个人独立开发项目，于 2026 年 9 月正式建立 Git 版本控制。
- 核心业务闭环已完成：创建 / 加入 / 上传 / 浏览 / 下载 / 删除 / 过期清理。
- 主要在 **Android** 上进行开发验证；**Web** 有专门的浏览器适配层（XHR 上传进度、Blob 下载）；iOS / 桌面平台工程目录完整，但验证有限，未宣称全平台稳定运行。
- 过期清理 Edge Function 已实现，Cron 调度需在 Supabase Dashboard 手动配置。
- 测试覆盖有限：`test/` 目前仅一个基础 widget 测试；无 CI/CD 流水线。

