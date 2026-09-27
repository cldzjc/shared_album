# 项目空间与 AI 行为约束规则

## 💾 数据库表结构 (Supabase Database Schema)

编写任何 Dart 数据模型（Model）或服务层（Service）时，必须严格对齐以下 Supabase 数据库字段和业务规则：

### 1. `profiles` 表 (用户表)

## Table `profiles`

### Columns

| Name | Type | Constraints |
| ------ | ------ | ------------- |
| `id` | `uuid` | Primary |
| `nickname` | `text` | |
| `avatar_url` | `text` | Nullable |
| `created_at` | `timestamptz` | |
| `updated_at` | `timestamptz` | |

### 2. `albums` 表 (相册表)

## Table `albums`

### Columns

| Name | Type | Constraints |
| ------ | ------ | ------------- |
| `id` | `uuid` | Primary |
| `name` | `text` | |
| `share_code` | `text` | Unique |
| `password_hash` | `text` | |
| `creator_id` | `uuid` | |
| `expires_at` | `timestamptz` | |
| `created_at` | `timestamptz` | |

### 3. `photos` 表 (照片表)

## Table `photos`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `album_id` | `uuid` |  |
| `file_url` | `text` |  |
| `storage_path` | `text` |  |
| `uploader_id` | `uuid` |  |
| `created_at` | `timestamptz` |  |

### 4. Storage 存储策略（当前执行：方案 A）

- 当前方案：**Supabase Edge Functions + 阿里云 OSS 直传**。
- 说明：客户端不再向 Supabase Storage 上传照片本体；仅通过数据库保存元数据（`file_url`、`storage_path`）。

### 5. RLS 与权限边界 (Row Level Security)

三张业务表必须启用 RLS；默认不关闭安全边界。若前端仍沿用当前 MVP 的直连模式，必须严格按以下规则配置策略：

#### `profiles`

- `select`: 仅允许 `auth.uid() = id` 的用户读取自己的资料。
- `insert`: 仅允许 `auth.uid() = id` 的用户创建自己的资料。
- `update`: 仅允许 `auth.uid() = id` 的用户更新自己的资料。
- `delete`: 默认不开放，保留后台手动清理能力即可。

#### `albums`

- `insert`: 仅允许已登录用户创建，且 `creator_id = auth.uid()`。
- `select`: 若继续使用“分享码 + 密码”直连查询，则应改为由 RPC/安全函数返回脱敏结果；不建议直接对匿名用户开放整行读取，因为 `password_hash` 不应暴露给前端。
- `update` / `delete`: 仅允许 `creator_id = auth.uid()`。

#### `photos`

- `insert`: 仅允许已登录用户上传，且 `uploader_id = auth.uid()`。
- `select`: 若前端直接查询照片表，则应限制为相册创建者本人；若要支持“输入分享码即可浏览”，应改为通过 RPC 或安全视图校验后返回照片列表，不建议匿名用户直接整行读取。
- `update` / `delete`: 仅允许 `uploader_id = auth.uid()` 或相册创建者按业务需要管理。

#### 设计原则

- `password_hash` 只存于 `public.albums`，不进入 `auth.users`。
- `nickname`、`avatar_url` 等业务资料只存于 `public.profiles`。
- `auth.users` 只负责认证身份、邮箱、密码哈希、恢复信息等系统级内容；业务代码不要尝试从前端读取密码。

#### 推荐补充

- 如果后续要严格支持“游客通过分享码 + 密码浏览相册”，建议新增 RPC 或安全视图专门做校验，不要直接把 `albums` / `photos` 的整行读取暴露给匿名用户。

### 6. `album_participants` 表 (参与关系表，用于主页展示"我参与过哪些相册")

- `album_id`: uuid (primary key, references public.albums.id)
- `user_id`: uuid (primary key, references auth.users)
- `role`: text (角色标记，'creator' 或 'member')
- `joined_at`: timestamptz (加入时间，非空，默认 now())

#### `album_participants` 的 RLS 规则

- `select`: 仅允许 `auth.uid() = user_id` 的用户查看自己的参与记录。
- `insert`: 仅允许 `auth.uid() = user_id` 的用户创建自己的参与记录。
- `update`: 允许记录所有者或相册创建者修改。
- `delete`: 允许记录所有者或相册创建者删除。

### 7. 建表与 RLS SQL 基线

```sql
-- 1. 创建 album_participants 表（参与关系）
create table if not exists public.album_participants (
  album_id uuid not null references public.albums(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (album_id, user_id)
);

-- 2. 启用 RLS
alter table public.album_participants enable row level security;

-- 3. album_participants RLS 策略
-- 查看自己的参与记录
drop policy if exists "participants_select_own" on public.album_participants;
create policy "participants_select_own"
on public.album_participants
for select
using (auth.uid() = user_id);

-- 用户可以创建自己的参与记录
drop policy if exists "participants_insert_own" on public.album_participants;
create policy "participants_insert_own"
on public.album_participants
for insert
with check (auth.uid() = user_id);

-- 用户或相册创建者可以更新参与记录
drop policy if exists "participants_update_own_or_creator" on public.album_participants;
create policy "participants_update_own_or_creator"
on public.album_participants
for update
using (
  auth.uid() = user_id
  or exists (
    select 1
    from public.albums a
    where a.id = album_participants.album_id
      and a.creator_id = auth.uid()
  )
)
with check (
  auth.uid() = user_id
  or exists (
    select 1
    from public.albums a
    where a.id = album_participants.album_id
      and a.creator_id = auth.uid()
  )
);

-- 用户或相册创建者可以删除参与记录
drop policy if exists "participants_delete_own_or_creator" on public.album_participants;
create policy "participants_delete_own_or_creator"
on public.album_participants
for delete
using (
  auth.uid() = user_id
  or exists (
    select 1
    from public.albums a
    where a.id = album_participants.album_id
      and a.creator_id = auth.uid()
  )
);

-- 4. （可选）如果需要更新 albums / photos 的 select 策略以支持参与者访问

-- 更新 albums select 策略以支持参与者查看
drop policy if exists "albums_select_creator_or_participant" on public.albums;
create policy "albums_select_creator_or_participant"
on public.albums
for select
using (
  auth.uid() = creator_id
  or exists (
    select 1
    from public.album_participants p
    where p.album_id = albums.id
      and p.user_id = auth.uid()
  )
);

-- 更新 photos select 策略以支持参与者查看
drop policy if exists "photos_select_creator_or_participant" on public.photos;
create policy "photos_select_creator_or_participant"
on public.photos
for select
using (
  exists (
    select 1
    from public.albums a
    where a.id = photos.album_id
      and (
        a.creator_id = auth.uid()
        or exists (
          select 1
          from public.album_participants p
          where p.album_id = a.id
            and p.user_id = auth.uid()
        )
      )
  )
);

-- storage.objects：配合私有 bucket album-photos
-- 约定：对象名 name 使用 upload 端的 storagePath，格式为 `albumId/timestamp-filename`
-- 这样可以通过 split_part(name, '/', 1) 取出 albumId 做权限校验。

drop policy if exists "storage_select_album_files" on storage.objects;
create policy "storage_select_album_files"
on storage.objects
for select
using (
  bucket_id = 'album-photos'
  and exists (
    select 1
    from public.albums a
    where split_part(storage.objects.name, '/', 1) = a.id::text
      and (
        a.creator_id = auth.uid()
        or exists (
          select 1
          from public.album_participants p
          where p.album_id = a.id
            and p.user_id = auth.uid()
        )
      )
  )
);

drop policy if exists "storage_insert_album_files" on storage.objects;
create policy "storage_insert_album_files"
on storage.objects
for insert
with check (
  bucket_id = 'album-photos'
  and auth.uid() is not null
  and exists (
    select 1
    from public.albums a
    where split_part(storage.objects.name, '/', 1) = a.id::text
      and (
        a.creator_id = auth.uid()
        or exists (
          select 1
          from public.album_participants p
          where p.album_id = a.id
            and p.user_id = auth.uid()
        )
      )
  )
);

drop policy if exists "storage_update_album_files" on storage.objects;
create policy "storage_update_album_files"
on storage.objects
for update
using (
  bucket_id = 'album-photos'
  and (
    owner = auth.uid()
    or exists (
      select 1
      from public.albums a
      where split_part(storage.objects.name, '/', 1) = a.id::text
        and a.creator_id = auth.uid()
    )
  )
)
with check (
  bucket_id = 'album-photos'
  and (
    owner = auth.uid()
    or exists (
      select 1
      from public.albums a
      where split_part(storage.objects.name, '/', 1) = a.id::text
        and a.creator_id = auth.uid()
    )
  )
);

drop policy if exists "storage_delete_album_files" on storage.objects;
create policy "storage_delete_album_files"
on storage.objects
for delete
using (
  bucket_id = 'album-photos'
  and (
    owner = auth.uid()
    or exists (
      select 1
      from public.albums a
      where split_part(storage.objects.name, '/', 1) = a.id::text
        and a.creator_id = auth.uid()
    )
  )
);
```

---

## ☁️ Edge Functions + OSS 方案 A落地说明

### 1) Supabase Edge Function 环境变量

在 Supabase 项目中为函数配置以下 secrets：

- `OSS_ACCESS_KEY_ID`
- `OSS_ACCESS_KEY_SECRET`
- `OSS_BUCKET`
- `OSS_REGION`

建议通过 `supabase secrets set` 配置，不要硬编码在代码中。

### 2) 函数命名约定

- 上传签名函数名：`oss-sign-upload`

Flutter 客户端默认调用该函数名；如需改名，需同步修改 `photo_upload_service.dart`。

### 3) Edge Function 参考实现（Deno）

以下为当前项目可直接使用的模板（POST 请求，返回 `uploadUrl/publicUrl/objectKey`）：

```ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

async function hmacSha1(key: string, data: string) {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(key),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(data));
  return btoa(String.fromCharCode(...new Uint8Array(signature)));
}

function inferExt(filename: string, contentType: string) {
  const pos = filename.lastIndexOf(".");
  if (pos !== -1) return filename.substring(pos).toLowerCase();
  if (contentType === "image/png") return ".png";
  if (contentType === "image/webp") return ".webp";
  if (contentType === "image/gif") return ".gif";
  if (contentType === "image/heic") return ".heic";
  return ".jpg";
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 });
  }

  const { filename, contentType, album_id, uploader_id } = body ?? {};
  if (!filename || !album_id || !uploader_id) {
    return new Response(
      JSON.stringify({ error: "filename, album_id, uploader_id required" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const accessKeyId = Deno.env.get("OSS_ACCESS_KEY_ID")!;
  const accessKeySecret = Deno.env.get("OSS_ACCESS_KEY_SECRET")!;
  const bucket = Deno.env.get("OSS_BUCKET")!;
  const region = Deno.env.get("OSS_REGION")!;

  const timestamp = Date.now();
  const ext = inferExt(String(filename), String(contentType || "image/jpeg"));
  const objectKey = `shared_album/${album_id}/${uploader_id}/${timestamp}${ext}`;
  const expires = Math.floor(Date.now() / 1000) + 60;

  const canonicalString = `PUT\n\n${contentType || "image/jpeg"}\n${expires}\n/${bucket}/${objectKey}`;
  const signature = await hmacSha1(accessKeySecret, canonicalString);

  const uploadUrl =
    `https://${bucket}.${region}.aliyuncs.com/${objectKey}` +
    `?OSSAccessKeyId=${accessKeyId}` +
    `&Expires=${expires}` +
    `&Signature=${encodeURIComponent(signature)}`;

  const publicUrl = `https://${bucket}.${region}.aliyuncs.com/${objectKey}`;

  return new Response(
    JSON.stringify({ uploadUrl, publicUrl, objectKey, expires }),
    { headers: { "Content-Type": "application/json" } },
  );
});
```

### 4) Flutter 客户端调用流程（已落地）

- 调用 `oss-sign-upload` 获取 `uploadUrl/publicUrl/objectKey`。
- 使用 `HTTP PUT` 直传图片二进制到 OSS。
- 将 `publicUrl` 写入 `photos.file_url`，将 `objectKey` 写入 `photos.storage_path`。
- 相册详情页直接读取 `photos.file_url` 展示。

### 5) 方案 A 说明

- 方案 A 依赖 OSS 对象可公网读取（通过 `publicUrl` 直接访问）。
- 若后续升级为私有读权限，需新增下载签名函数（方案 B）。

---

## 🗺️ 专属开发流程规划 (Development Roadmap)

请严格遵循以下里程碑推进项目，当前正在执行 **【步骤 11】**：

- [x] **步骤 1：验证 Supabase 连接成功** (已完成，主页已成功连通并在前端展示状态)
- [x] **步骤 2：在云端创建好 albums、photos、profiles 三张表与函数** (已在云端部署完毕)
- [x] **步骤 3：做创建相册页面** (已完成，包含表单 UI 与登录拦截机制)
- [x] **步骤 4：写创建相册入库** (已完成，包含 Riverpod 状态提交、防碰撞分享码及密码哈希写入)
- [x] **步骤 5：做加入相册** (已完成，包括密码及过期校验、加入流及相册照片流详情页展示)
- [x] **步骤 6：再补登录注册** (已完成，包含邮箱注册/登录、profiles 对接、全局 Auth 状态保活)
- [x] **步骤 7：上传照片** (已完成 ✅，当前已切换为 Edge Functions + OSS)
  - `photo_upload_service.dart` 调用 `oss-sign-upload` 获取 OSS 预签名上传地址
  - 客户端使用 `HTTP PUT` 直传图片二进制到阿里云 OSS
  - 上传成功后，把 `publicUrl` 写入 `photos.file_url`，把 `objectKey` 写入 `photos.storage_path`
  - `photo_upload_provider.dart` 管理上传状态（单/多图支持、进度、成功/失败提示）
  - `album_detail_page.dart` 集成上传入口、登录引导和上传后刷新
  - `image_picker: ^1.0.4` 已在依赖中
  - 编译通过无错误
- [x] **步骤 8：查看照片** (已完成 ✅，直接读取 OSS 公网地址)
  - `album_photos_provider.dart` 直接读取 `photos.file_url` 展示照片，不再依赖 Supabase Storage 签名 URL
  - `photo_download_service.dart` 处理照片下载和本地存储
  - `photo_download_provider.dart` 管理下载状态
  - `album_detail_page.dart` 已更新照片预览界面，支持文件名、上传时间、互动式缩放和加载进度显示
  - `http: ^1.0.0` 和 `path_provider: ^2.1.0` 已在依赖中
  - 编译通过无错误
- [x] **步骤 9：下载照片** (已完成 ✅，直接拉取 OSS 公网地址到本地缓存)
  - `photo_download_service.dart` 使用 `http.Client().send()` 流式下载图片，支持进度回调、重复下载判断和本地缓存目录 `shared_album_photos`
  - `photo_download_provider.dart` 管理下载中、成功、失败、已下载状态，以及进度文案切换
  - `album_detail_page.dart` 的预览弹窗已接入下载按钮、进度条和保存完成提示
  - `path_provider: ^2.1.0` 和 `http: ^1.0.0` 已在依赖中
  - 编译通过无错误
- [x] **步骤 10：删除照片** (已完成 ✅)
  - `photo_delete_service.dart`：仅发送 `photoId` + `resourceType: 'photo'` 到统一的 `delete-resource` Edge Function，不直接接触 OSS 路径
  - `supabase/functions/delete-resource/index.ts`：统一删除入口，负责鉴权、反查 `photos.storage_path`、先删 OSS 再删数据库记录
  - `album_detail_page.dart`：在预览弹窗中提供删除按钮，带二次确认、权限控制、删除后自动刷新列表并关闭弹窗
  - 删除顺序：先删 OSS 原图，再删数据库记录；若 OSS 删除失败，数据库记录不删除，保持一致性
- [ ] **步骤 11：免费版自动过期**
  - 目标：免费版相册有效期固定 24 小时，创建时直接写入 `expires_at = created_at + 24h`，到期后由后端自动清理，不依赖 Flutter 在线。
  - `album_detail_page.dart`：只负责展示剩余时间倒计时与到期拦截提示，不负责删除动作；倒计时组件建议独立封装为 `AlbumCountdownWidget`，只做局部刷新，不让整个页面每秒重建。
  - `cleanup-expired-albums` Edge Function：查询 `expires_at <= now()` 的相册，单次最多处理 `limit 20` 个相册，读取相册下全部照片，**不通过 HTTP 调用 `delete-resource`**，而是直接复用共享删除方法（`shared/delete_photo.ts`），批量删除 OSS 原图、`photos` 记录，再删除 `albums` 记录。
  - `Supabase Cron`：每 5 分钟触发一次 `cleanup-expired-albums`，确保过期资源在后台持续收敛，避免每分钟调度造成不必要开销。
  - `join_album_provider.dart` / `album_photos_provider.dart`：继续保留过期过滤，避免前端误展示已过期相册；若用户仍停留在已过期页面，下一次请求应返回“该相册已过期”，再自动返回首页/列表，不弹“删除成功”类 Toast。
  - 复用原则：`delete-resource` 与 `cleanup-expired-albums` 共享同一套删除逻辑，`delete-resource` 负责单个资源删除入口，`cleanup-expired-albums` 负责批量编排，不重复写 OSS 删除、鉴权和 JSON 解析逻辑。
  - 统计日志：`cleanup-expired-albums` 最后返回 `expiredAlbums`、`deletedPhotos`、`failedAlbums`、`failedPhotos`，方便在 Supabase Logs 一眼看出今日清理量。

---

## 📋 技术栈与架构规范 (Tech Stack & Architecture Guidelines)

### 1. 核心技术选型 (Core Technologies)

- **UI 框架**：Flutter (Material 3 风格，以 `Colors.teal` 为主题种子色)
- **状态管理**：Riverpod 3.x (遵循**手动声明模式**，不引入 `build_runner` 代码生成工具)
- **后端服务**：Supabase Flutter SDK (集成 Auth 身份鉴权、PostgreSQL 数据存储)
- **文件存储（当前实现）**：Supabase Edge Functions + 阿里云 OSS 直传；客户端先向 Edge Function 申请 OSS 预签名上传地址，再将 `publicUrl` 和 `storage_path` 写入数据库。
- **安全辅助**：`crypto` 包 (用于客户端 SHA-256 密码加盐哈希，避免明文传输与存储密码)

### 2. 目录结构与分层设计 (Architecture Layers)

应用层代码必须遵循以下分层组织规范：

- `lib/config/`：存放全局静态配置（如 [app_config.dart](file:///E:/flutter_projects/shared_album/lib/config/app_config.dart)）。
- `lib/services/`：单例工具和服务类封装（如 [supabase_client_manager.dart](file:///E:/flutter_projects/shared_album/lib/services/supabase_client_manager.dart)）。
- `lib/providers/`：状态管理层。每个业务模块定义独立的 Notifier，暴露数据给 UI 层（如 [join_album_provider.dart](file:///E:/flutter_projects/shared_album/lib/providers/join_album_provider.dart)）。
- `lib/pages/`：视图层。页面继承 `ConsumerWidget` 或 `ConsumerStatefulWidget`，仅负责 UI 呈现与用户交互。

### 3. Riverpod 3.x 状态管理规范 (Riverpod Style)

- **免生成器声明**：不使用 `@riverpod` 宏生成代码，而是继承 `AsyncNotifier<T>` 并手动暴露。
- **Family 传参规范**：
  - Notifier 类的构造函数必须接收参数（如 `AlbumPhotosNotifier(this.albumId)`），并提供无参的 `build()` 方法。
  - Provider 必须使用 `AsyncNotifierProvider.autoDispose.family` 进行声明，格式为：`(ref, arg) => Notifier(arg)`。
- **生命周期管理**：状态管理器统一使用 `.autoDispose` 确保页面关闭时及时销毁状态，防止内存泄露及缓存错乱。

### 4. 命名与代码风格 (Naming Conventions)

- **文件命名**：采用小写加下划线 `snake_case` (如 `album_detail_page.dart`)。
- **类名命名**：采用大驼峰 `PascalCase`，且应带有明确的类型后缀：
  - 页面/视图：`*Page` (如 `JoinPage`)。
  - 数据模型：`*Model` (如 `AlbumModel`)。
  - 状态管理：`*Notifier` (如 `JoinAlbumNotifier`) / `*Provider` (如 `joinAlbumProvider`)。
- **方法/属性**：采用小驼峰 `camelCase`，私有变量/方法以 `_` 开头。

### 5. 安全性与异常处理 (Security & Error Handling)

- **密码存储**：任何涉及密码的存储与网络传输，必须在客户端对原始密码进行单向 SHA-256 哈希，比对与入库一律使用哈希值。
- **异常边界**：所有网络请求、Supabase 交互必须用 `try-catch` 或 `AsyncValue.guard` 妥善包裹，并向 UI 层抛出友好异常，坚决不允许抛出未捕获的报错到顶层。
- **登录状态校验**：对权限分级进行严格拦截。创建与上传入口必须执行 `auth.currentUser == null` 校验。

---

## 🎯 第一版 MVP 核心功能与业务规则 (MVP Product Definitions)

你在编写任何页面逻辑、路由跳转和状态订阅时，必须严格遵守以下 MVP 业务边界：

### 1. 登录与身份体系

- **不强制登录**：默认支持访客模式进入。
- **权限分级**：
  - **未登录用户 (游客/访客)**：可直接进入主页、可通过分享码+密码加入并浏览相册。
  - **已登录用户**：拥有完整权限，可创建相册、上传照片、下载照片。

### 2. 核心页面功能

- **【主页入口 (Home Page)】**：
  - 核心 UI：两个醒目的按钮——“创建相册”和“加入相册”。
  - 逻辑：点击“创建相册”时，需检查用户是否登录，若未登录则引导至登录页。
- **【创建相册 (Create Page)】**：
  - **仅限已登录用户访问**。
  - 表单字段：用户昵称（若 profiles 里没有）、相册名（`name`）、相册访问密码（`password_hash`）、自动或手动生成的唯一分享码（`share_code`）。
- **【加入相册 (Join Page)】**：
  - **不强制登录**。输入正确的 `share_code` 和密码即可校验进入。
- **【相册展示页 (Album Detail Page)】**：
  - UI 布局：顶部清晰显示 “相册名 #分享码”；中间为照片流/网格布局（Grid View）；底部常驻一个“上传照片”的悬浮/操作按钮。
  - 权限控制：浏览照片不强制登录，但点击下方“上传/下载”按钮时，建议弹出提示并引导登录。

### 3. 数据与生命周期约束

- **24h 过期销毁**：所有创建的相册在数据库中对应的 `expires_at` 默认设置为创建时间往后推 24 小时。一旦当前时间大于 `expires_at`，该相册即视为失效，前端应拒绝访问。
- **存储规范**：照片本体（文件）当前通过 Supabase Edge Functions + 阿里云 OSS 直传；相册和照片的元数据（URL、路径、创建人等）记录在对应的 `albums` 和 `photos` 数据库表中。

# 共享相册项目 - 图片资源生命周期与缓存策略（V1.0）

## 一、设计目标

本项目定位为共享云相册，而非本地相册或网盘。系统需要兼顾以下目标：

1. 浏览体验流畅，保证相册打开速度。
2. 尽可能减少 OSS 请求次数和流量成本。
3. 尽可能减少客户端本地存储占用。
4. 云端资源与本地缓存完全解耦。
5. 后续支持免费版与付费版两种不同生命周期策略。

---

## 二、图片资源模型

一张照片在系统中存在三种资源，而不是一种资源。

### 1. Thumbnail（缩略图）

作用：

- 相册列表浏览
- 瀑布流浏览
- 相册封面

特点：

- 永远优先加载缩略图
- 不承担高清浏览功能
- 长期缓存
- 文件体积尽可能小

缩略图存在的意义不是提高画质，而是降低 OSS 请求成本并提升浏览体验。

---

### 2. Original（原图）

作用：

- 用户点击图片后的高清浏览
- 图片下载
- 保存到系统相册

特点：

- 按需下载
- 不参与相册浏览
- 不长期缓存
- 浏览结束后可释放

原图属于云资源，不属于本地资源。

---

### 3. Saved（系统相册）

作用：

用户主动保存后的手机资产。

特点：

- 用户主动触发
- 写入系统相册
- 与 App 缓存完全独立
- App 删除缓存不会影响系统相册

---

## 三、缓存设计

缓存属于客户端行为，不属于业务数据。

服务器不记录缓存。

数据库不管理缓存。

Edge Function 不负责缓存。

缓存仅用于提升用户体验。

---

### 一级缓存（Thumbnail Cache）

缓存对象：

缩略图。

特点：

- 浏览时优先读取
- 不频繁删除
- 图片存在则缓存可以存在
- 图片删除时同步删除对应缓存

一级缓存的目标：

减少 OSS GET 请求。

---

### 二级缓存（Preview Cache）

缓存对象：

用户真正点击浏览过的高清图片。

特点：

- 按需缓存
- 不永久保存
- 用户退出相册后可清理
- 或采用 LRU 自动淘汰

二级缓存的目标：

提升连续浏览体验。

---

## 四、缓存生命周期

缓存不是独立生命周期，而是依附于图片资源。

图片删除：

对应缩略图缓存删除。

对应高清缓存删除。

图片移动：

缓存更新。

图片不存在：

缓存不存在。

---

## 五、免费版策略

免费版定位：

临时共享工具。

特点：

- 相册具有生命周期。
- 相册到期后自动销毁。
- 数据库删除。
- OSS 删除。
- 缩略图缓存删除。
- 高清缓存删除。

免费版不保留历史缓存。
我们之前规划过免费版的自动过期和资源生命周期，到时候完全可以顺手加一个"孤儿资源扫描"任务，把数据库里不存在但 OSS 残留，或者 OSS 已删但数据库残留的情况定期修正
---

## 六、付费版策略

付费版定位：

长期云相册。

特点：

缩略图长期缓存。

高清图仅缓存最近浏览内容。

缓存采用容量控制与 LRU 管理。

用户购买的是云存储，而不是本地缓存。

缓存只是体验优化，不作为付费权益。

---

## 七、资源唯一标识

系统内部所有图片均使用 PhotoID 作为唯一身份。

文件名仅属于存储实现。

任何缓存、数据库、OSS 路径均围绕 PhotoID 建立关联。

未来即使迁移至其他对象存储服务，也无需修改业务逻辑。

---

## 八、数据库原则

数据库仅维护图片资源。

数据库不维护客户端缓存。

数据库仅需要记录：

- PhotoID
- 原图地址
- 缩略图地址
- 图片元数据

缓存状态全部由客户端维护。

---

## 九、Edge Function 原则

Edge Function 仅负责云资源生命周期。

包括：

- 上传资源
- 删除资源
- 清理 OSS 文件

Edge Function 不参与客户端缓存管理。

---

## 十、后续开发顺序

阶段一：

完成上传、浏览、保存到系统相册、删除等基础功能，形成完整业务闭环。

阶段二：

完善图片资源模型，引入缩略图资源。

阶段三：

实现统一缓存管理，包括缩略图缓存与高清缓存。

阶段四：

增加缓存统计、容量控制、LRU 淘汰、自动清理等优化能力。

阶段五：

进一步实现智能预加载、离线浏览、收藏相册缓存等高级功能。

---

## 📐 Media Architecture（图片资源加载链路）

### 缩略图链路（Grid / 列表 / 封面）

```
阿里云 OSS (原图存储)
  │
  └─ ?x-oss-process=style/thumbnail ──→ 缩略图 (~15-30KB WebP)
                                        │
                                        ▼
                              PhotoImageService.getThumbnail(fileUrl)
                                        │
                                        ▼
                              CachedNetworkImage (UI 组件)
                                        │
                                        ▼
                              PhotoCacheService.thumbnails
                              (DefaultCacheManager, ~200MB LRU)
                                        │
                                        ▼
                              flutter_cache_manager (磁盘 + 内存缓存)
                                        │
                                        ▼
                              UI 渲染 (秒加载)
```

### 原图链路（全屏预览 / 下载）

```
阿里云 OSS (原图存储)
  │
  └─ PhotoImageService.getOriginal(fileUrl) ──→ 原图 URL
                                        │
                                        ▼
                              CachedNetworkImage (预览弹窗)
                              OR http.Client (下载到沙盒)
                                        │
                                        ▼
                              PhotoCacheService.previews
                              (独立 CacheManager, ~200MB LRU)
                                        │
                                        ▼
                              flutter_cache_manager
                                        │
                                        ├── 全屏预览 (原图缓存，LRU 淘汰)
                                        └── 下载 → 沙盒 shared_album_photos/ → Gal → 系统相册
```

### 图片 URL 入口（唯一修改点）

所有图片 URL 变换集中在 [lib/services/photo_image_service.dart](lib/services/photo_image_service.dart)：

| 方法 | 用途 | URL 变换 |
| --- | --- | --- |
| `getThumbnail(fileUrl)` | 网格列表、相册封面 | `fileUrl?x-oss-process=image/auto-orient,1/resize,m_fill,w_400,h_400/quality,q_51/…` |
| `getPreview(fileUrl)` | 全屏浏览 | `fileUrl`（当前同原图，预留中等尺寸） |
| `getOriginal(fileUrl)` | 下载、保存到系统相册 | `fileUrl`（原图不变） |

未来更换存储服务（七牛 / R2 / Supabase Storage）只需修改此文件。

### 缓存管理层

[lib/services/photo_cache_service.dart](lib/services/photo_cache_service.dart) 是缓存操作的唯一入口：

- `thumbnails` — 缩略图缓存，全局共享 `DefaultCacheManager`
- `previews` — 预览原图缓存，独立 `CacheManager`，容量约 200MB
- `clearPhoto(photo)` — 清除单张照片的全部缓存
- `clearAlbum(photos)` — 清除整个相册的缓存
- `prefetchThumbnails(photos, startIndex, count)` — 后台预加载（ScrollController 驱动）
- **不自己实现 LRU**，全部委托 `flutter_cache_manager`

### 系统相册隔离

`Gal.putImage()` 写入手机系统相册，物理路径与 App 沙盒及 `flutter_cache_manager` 缓存目录完全隔离。App 缓存清理不会影响用户已保存到系统相册的照片。

---

## 十一、设计原则

本项目遵循以下原则：

- 云资源与客户端缓存解耦。
- 浏览始终优先缩略图。
- 高清资源按需下载。
- 用户主动保存才写入系统相册。
- 缓存服务于体验，不承担数据存储职责。
- 所有图片以 PhotoID 为唯一标识。
- 所有架构设计优先考虑长期可维护性，而不是短期实现速度。
