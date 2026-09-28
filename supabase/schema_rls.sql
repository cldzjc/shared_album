-- =============================================================
-- Shared Album 数据库基线：建表 + Row Level Security 策略
-- 对应客户端源码 lib/ 与 Edge Functions supabase/*.ts
-- 执行环境：Supabase PostgreSQL
-- =============================================================

-- 1. profiles（用户资料表）
--    account_type: 'guest'（匿名游客） / 'normal'（已绑定邮箱密码的正式用户）
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text,
  avatar_url text,
  account_type text not null default 'guest',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2. albums（相册表）
create table if not exists public.albums (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  share_code text not null unique,
  password_hash text not null,
  creator_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

-- 3. photos（照片元数据表，文件本体存于阿里云 OSS）
create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.albums(id) on delete cascade,
  file_url text not null,
  storage_path text not null,
  uploader_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- 4. album_participants（参与关系表，用于主页展示“我参与过哪些相册”）
create table if not exists public.album_participants (
  album_id uuid not null references public.albums(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (album_id, user_id)
);

-- =============================================================
-- 启用 RLS
-- =============================================================
alter table public.profiles enable row level security;
alter table public.albums enable row level security;
alter table public.photos enable row level security;
alter table public.album_participants enable row level security;

-- =============================================================
-- profiles：用户只能读写自己的资料
-- =============================================================
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles for select
using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
on public.profiles for insert
with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles for update
using (auth.uid() = id)
with check (auth.uid() = id);

-- profiles.delete 默认不开放，保留后台手动清理能力

-- =============================================================
-- albums：创建者可管理，创建者与参与者可查看
-- =============================================================
drop policy if exists "albums_insert_creator" on public.albums;
create policy "albums_insert_creator"
on public.albums for insert
with check (auth.uid() = creator_id);

drop policy if exists "albums_select_creator_or_participant" on public.albums;
create policy "albums_select_creator_or_participant"
on public.albums for select
using (
  auth.uid() = creator_id
  or exists (
    select 1
    from public.album_participants p
    where p.album_id = albums.id
      and p.user_id = auth.uid()
  )
);

drop policy if exists "albums_update_creator" on public.albums;
create policy "albums_update_creator"
on public.albums for update
using (auth.uid() = creator_id)
with check (auth.uid() = creator_id);

drop policy if exists "albums_delete_creator" on public.albums;
create policy "albums_delete_creator"
on public.albums for delete
using (auth.uid() = creator_id);

-- =============================================================
-- photos：上传者插入；相册创建者或参与者可查看；
--         删除/更新仅限上传者或相册创建者
-- =============================================================
drop policy if exists "photos_insert_uploader" on public.photos;
create policy "photos_insert_uploader"
on public.photos for insert
with check (auth.uid() = uploader_id);

drop policy if exists "photos_select_creator_or_participant" on public.photos;
create policy "photos_select_creator_or_participant"
on public.photos for select
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

drop policy if exists "photos_update_uploader_or_creator" on public.photos;
create policy "photos_update_uploader_or_creator"
on public.photos for update
using (
  uploader_id = auth.uid()
  or exists (
    select 1 from public.albums a
    where a.id = photos.album_id and a.creator_id = auth.uid()
  )
)
with check (
  uploader_id = auth.uid()
  or exists (
    select 1 from public.albums a
    where a.id = photos.album_id and a.creator_id = auth.uid()
  )
);

drop policy if exists "photos_delete_uploader_or_creator" on public.photos;
create policy "photos_delete_uploader_or_creator"
on public.photos for delete
using (
  uploader_id = auth.uid()
  or exists (
    select 1 from public.albums a
    where a.id = photos.album_id and a.creator_id = auth.uid()
  )
);

-- =============================================================
-- album_participants：记录所有者或相册创建者可管理
-- =============================================================
drop policy if exists "participants_select_own" on public.album_participants;
create policy "participants_select_own"
on public.album_participants for select
using (auth.uid() = user_id);

drop policy if exists "participants_insert_own" on public.album_participants;
create policy "participants_insert_own"
on public.album_participants for insert
with check (auth.uid() = user_id);

drop policy if exists "participants_update_own_or_creator" on public.album_participants;
create policy "participants_update_own_or_creator"
on public.album_participants for update
using (
  auth.uid() = user_id
  or exists (
    select 1 from public.albums a
    where a.id = album_participants.album_id and a.creator_id = auth.uid()
  )
)
with check (
  auth.uid() = user_id
  or exists (
    select 1 from public.albums a
    where a.id = album_participants.album_id and a.creator_id = auth.uid()
  )
);

drop policy if exists "participants_delete_own_or_creator" on public.album_participants;
create policy "participants_delete_own_or_creator"
on public.album_participants for delete
using (
  auth.uid() = user_id
  or exists (
    select 1 from public.albums a
    where a.id = album_participants.album_id and a.creator_id = auth.uid()
  )
);

-- =============================================================
-- storage.objects：私有 bucket album-photos
-- 对象名约定：albumId/timestamp-filename，
-- 通过 split_part(name, '/', 1) 取出 albumId 做权限校验。
-- =============================================================
drop policy if exists "storage_select_album_files" on storage.objects;
create policy "storage_select_album_files"
on storage.objects for select
using (
  bucket_id = 'album-photos'
  and exists (
    select 1 from public.albums a
    where split_part(storage.objects.name, '/', 1) = a.id::text
      and (
        a.creator_id = auth.uid()
        or exists (
          select 1 from public.album_participants p
          where p.album_id = a.id and p.user_id = auth.uid()
        )
      )
  )
);

drop policy if exists "storage_insert_album_files" on storage.objects;
create policy "storage_insert_album_files"
on storage.objects for insert
with check (
  bucket_id = 'album-photos'
  and auth.uid() is not null
  and exists (
    select 1 from public.albums a
    where split_part(storage.objects.name, '/', 1) = a.id::text
      and (
        a.creator_id = auth.uid()
        or exists (
          select 1 from public.album_participants p
          where p.album_id = a.id and p.user_id = auth.uid()
        )
      )
  )
);

drop policy if exists "storage_update_album_files" on storage.objects;
create policy "storage_update_album_files"
on storage.objects for update
using (
  bucket_id = 'album-photos'
  and (
    owner = auth.uid()
    or exists (
      select 1 from public.albums a
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
      select 1 from public.albums a
      where split_part(storage.objects.name, '/', 1) = a.id::text
        and a.creator_id = auth.uid()
    )
  )
);

drop policy if exists "storage_delete_album_files" on storage.objects;
create policy "storage_delete_album_files"
on storage.objects for delete
using (
  bucket_id = 'album-photos'
  and (
    owner = auth.uid()
    or exists (
      select 1 from public.albums a
      where split_part(storage.objects.name, '/', 1) = a.id::text
        and a.creator_id = auth.uid()
    )
  )
);
