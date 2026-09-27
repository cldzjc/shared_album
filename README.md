# Shared Album 共享相册

一个基于 Flutter + Supabase + 阿里云 OSS 开发的临时共享相册。

主要用于聚会、活动等多人一起拍照的场景。创建相册后生成一个 6 位数字分享码和访问密码，其他人无需注册账号即可加入并浏览照片。正式账号可以上传、下载和管理照片，相册到期后由后台任务自动清理云端资源。

这是一个个人独立开发项目，从产品设计、Flutter 客户端、数据库、对象存储到后端定时任务均由本人完成。

## 项目功能

* 邮箱注册 / 登录
* 游客加入相册，无需注册即可浏览
* 创建相册，自动生成 6 位数字分享码和访问密码
* 多张照片选择与上传
* OSS 直传及上传进度显示
* 照片缩略图网格浏览
* 全屏预览、手势缩放
* 照片下载并保存到系统相册
* 照片删除及权限校验
* 相册 24 小时自动过期
* Supabase Cron 定时清理过期相册
* 缩略图、预览图和原图分级加载
* 本地图片缓存
* Web / PWA 浏览器适配

## 技术栈

| 模块   | 技术                                          |
| ---- | ------------------------------------------- |
| 客户端  | Flutter / Dart                              |
| 状态管理 | Riverpod 3.x                                |
| 用户认证 | Supabase Auth                               |
| 数据库  | PostgreSQL / PostgREST                      |
| 数据权限 | Row Level Security（RLS）                     |
| 后端逻辑 | Supabase Edge Functions / Deno / TypeScript |
| 对象存储 | 阿里云 OSS                                     |
| 图片缓存 | flutter_cache_manager                       |
| 图片选择 | image_picker                                |
| 图片预览 | extended_image                              |
| 系统相册 | gal                                         |

## 项目结构

```text
lib/
├─ config/       全局配置和业务常量
├─ pages/        页面
├─ providers/    Riverpod 状态管理
├─ services/     上传、下载、缓存、图片 URL 等业务服务
└─ widgets/      通用组件

supabase/
├─ *.ts          Edge Functions
└─ *.sql         数据库相关 SQL

test/             Flutter 测试
android/
ios/
web/
linux/
macos/
windows/          Flutter 平台工程
```

## 整体架构

```text
                 Flutter App / Web
                        │
              Supabase Auth / RLS
                        │
          ┌─────────────┴─────────────┐
          │                           │
      PostgreSQL                Edge Functions
          │                           │
          │                  ┌────────┴────────┐
          │                  │                 │
          │              OSS 签名上传      删除 / 清理
          │                  │                 │
          └──────────────────┴─────────────────┘
                                    │
                                阿里云 OSS
```

客户端主要负责页面交互和业务状态，照片文件本身不经过 Supabase 数据库，而是通过 Edge Function 获取 OSS 预签名地址后直接上传到 OSS。

OSS 的 AccessKey 等敏感配置只放在 Edge Function 环境变量中，客户端只使用 Supabase 的公开客户端配置。

## 几个比较关键的实现

### 1. OSS 预签名直传

上传照片时，客户端先请求 `oss-sign-upload` 获取临时的 OSS PUT 地址，然后直接把图片上传到 OSS。

```text
Flutter
   │
   ├── 请求上传签名
   ▼
oss-sign-upload
   │
   └── 返回临时 PUT URL
              │
              ▼
         Flutter 直接上传
              │
              ▼
           阿里云 OSS
```

这样图片文件不会先上传到 Supabase，再由 Supabase 转存到 OSS，可以减少中间层的文件传输。

### 2. RLS 数据权限

数据库使用 Supabase PostgreSQL，并通过 RLS 控制不同用户能够访问的数据。

主要涉及：

* `albums`
* `photos`
* `profiles`
* `album_participants`

创建者、参与者和游客在业务上的操作范围不同，客户端不能单纯依靠 UI 隐藏按钮来实现权限控制。

### 3. 图片分级加载

照片浏览时没有直接加载原图，而是根据使用场景使用不同尺寸的图片：

```text
缩略图
  ↓
相册网格浏览

预览图
  ↓
全屏查看

原图
  ↓
下载 / 保存
```

缩略图使用 OSS 图片处理样式生成，减少列表页面加载时的图片大小。

这个方案主要解决了实际开发过程中遇到的一个问题：原图较大时，相册第一次打开会明显变慢，因此把“浏览”和“下载原图”拆成了不同的资源。

### 4. 图片缓存

客户端使用 `flutter_cache_manager` 对缩略图和预览图进行缓存。

相册列表反复进入时，不需要每次重新下载已经加载过的图片，同时对缓存进行淘汰，避免长期占用本地空间。

### 5. 照片删除

照片删除不是简单删除数据库记录。

正常删除流程为：

```text
用户请求删除
      ↓
检查权限
      ↓
删除 OSS 文件
      ↓
OSS 删除成功
      ↓
删除数据库记录
```

过期相册的后台清理也使用类似的删除流程。

### 6. 自动清理过期相册

相册创建时记录过期时间。

Supabase Cron 每 5 分钟触发一次 `cleanup-expired-albums`，后台查找已经过期的相册并清理对应的 OSS 文件和数据库记录。

因此即使用户已经关闭 App，相册仍然可以在后台完成清理。

### 7. 游客访问

项目没有使用匿名登录来实现游客模式。

游客通过：

```text
6 位分享码 + 访问密码
```

进入相册，并根据 `profiles.account_type` 区分 `guest` 和 `normal` 用户。

游客主要用于浏览和加入相册，创建、上传、下载、删除等操作需要正式账号。

## Edge Functions

项目目前主要使用以下 Edge Functions：

```text
oss-sign-upload
    获取 OSS 上传签名

delete-resource
    删除 OSS / 数据库资源

cleanup-expired-albums
    定时清理过期相册
```

OSS 的 AccessKey、Supabase Service Role Key 等服务端配置通过环境变量提供，没有提交到代码仓库。

## Web / PWA

项目除了 Android 外，也针对 Web 做了适配，可以作为 PWA 使用。

Web 环境与 Android 的文件处理方式不同，因此对上传和下载进行了单独处理：

* Web 上传使用浏览器文件选择和 XHR
* 上传过程中显示进度
* Web 下载使用浏览器 Blob 下载
* Android 使用系统文件和相册相关能力

目前主要开发和验证环境仍然是 Android，Web 已完成基本适配；iOS 和桌面平台保留 Flutter 工程，但没有宣称经过完整的平台稳定性验证。

## 本地运行

安装依赖：

```bash
flutter pub get
```

运行：

```bash
flutter run
```

完整运行项目需要自行准备 Supabase 和阿里云 OSS 环境。

### Supabase

需要准备：

* Supabase 项目
* PostgreSQL 数据库
* Auth
* RLS 策略
* Edge Functions

数据库结构和相关 SQL 位于：

```text
supabase/
```

### Edge Functions

部署 `supabase/` 下的 Edge Functions，并配置对应环境变量：

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY

OSS_ACCESS_KEY_ID
OSS_ACCESS_KEY_SECRET
OSS_BUCKET
OSS_REGION
```

### 阿里云 OSS

需要创建 OSS Bucket，并配置项目使用的图片处理样式，例如：

```text
small-photos
preview
```

### 定时任务

在 Supabase Dashboard 中配置 Cron，定期调用：

```text
cleanup-expired-albums
```

## 项目状态

目前已经完成主要业务闭环：

```text
创建相册
   ↓
分享
   ↓
加入相册
   ↓
浏览照片
   ↓
上传 / 下载 / 删除
   ↓
相册过期
   ↓
后台自动清理
```

项目主要在 Android 环境下进行开发和验证，同时完成了 Web / PWA 的基本适配。

目前测试覆盖仍然有限，`test/` 中只有基础 Widget 测试，也没有配置 CI/CD。

## 开发记录

这个项目使用 Git 进行版本管理，完整开发过程保留在 Git 提交历史中。

主要提交包括：

```text
chore: initialize project version control
docs: prepare project for public repository
```

后续开发也会继续通过 Git 记录功能修改和问题修复。

