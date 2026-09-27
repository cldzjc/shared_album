-- ============================================================
-- 相册参与者列表可见性策略（供相册详情页"参与者"面板使用）
-- ============================================================
-- ⚠️ 修复说明（2026-09-06）：
--   旧版策略在 album_participants 表的策略内部直接查询
--   album_participants 表自身，PostgreSQL 会对策略内的子查询
--   再次强制 RLS，形成无限递归，报错 42P17：
--     "infinite recursion detected in policy for relation album_participants"
--   该错误会让所有对 album_participants 的查询返回 500，
--   表现为首页"我的相册"一直转圈后显示"获取失败"。
--
--   修复方式：把"是否是相册成员"的判断下沉到
--   SECURITY DEFINER 函数（函数内部查询绕过 RLS），
--   策略只调用函数，递归链被切断。
--
-- 在 Supabase SQL Editor 中执行以下脚本即可生效：
-- ============================================================

-- 1. 创建安全辅助函数：当前登录用户是否是该相册的创建者或参与者
--    security definer：以函数 owner（postgres，超级用户）身份执行，
--    内部查询不受 RLS 限制，从而避免策略递归。
create or replace function public.is_album_member(album_uuid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.albums a
    where a.id = album_uuid
      and a.creator_id = auth.uid()
  )
  or exists (
    select 1
    from public.album_participants p
    where p.album_id = album_uuid
      and p.user_id = auth.uid()
  );
$$;

-- 允许 anon / authenticated 角色（PostgREST 请求角色）调用该函数
grant execute on function public.is_album_member(uuid) to anon, authenticated;

-- 2. 删除会引发 42P17 无限递归的旧策略
drop policy if exists "participants_select_album_members" on public.album_participants;

-- 3. 重建策略：只调用函数，不再在策略内直接引用本表
--    语义不变：相册创建者 / 相册参与者可查看该相册的全部参与者列表。
--    与原有 "participants_select_own"（仅本人可见自己的记录）
--    为叠加关系（多策略是 OR 语义），不扩大原安全边界。
create policy "participants_select_album_members"
on public.album_participants
for select
using (public.is_album_member(album_participants.album_id));

-- ============================================================
-- 可选加固：如果 albums 表的 select 策略
--   "albums_select_creator_or_participant" 也曾在日志中报 42P17，
-- 可将其一并替换为函数版本（幂等，可重复执行）：
-- ============================================================
-- drop policy if exists "albums_select_creator_or_participant" on public.albums;
-- create policy "albums_select_creator_or_participant"
-- on public.albums
-- for select
-- using (public.is_album_member(albums.id));
