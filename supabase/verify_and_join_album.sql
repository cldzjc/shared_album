-- verify_and_join_album
-- Security Definer RPC，负责加入相册全流程，Flutter 不再直查 albums / password_hash
-- 执行前请确认 Supabase 已启用 pgcrypto 扩展：create extension if not exists pgcrypto;

create or replace function public.verify_and_join_album(
  input_share_code text,
  input_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_album        public.albums%rowtype;
  v_hashed_input text;
  v_participant  record;
begin
  -- 0) 必须存在合法登录会话（匿名用户也属于合法登录）
  if auth.uid() is null then
    return jsonb_build_object(
      'success', false,
      'error', 'UNAUTHORIZED',
      'message', '用户身份无效，请重新启动应用后再试'
    );
  end if;
  -- 1) 参数校验
  if input_share_code is null or trim(input_share_code) = '' then
    return jsonb_build_object(
      'success', false,
      'error', 'INVALID_SHARE_CODE',
      'message', '分享码不能为空'
    );
  end if;

  if input_password is null or input_password = '' then
    return jsonb_build_object(
      'success', false,
      'error', 'INVALID_PASSWORD',
      'message', '密码不能为空'
    );
  end if;

  -- 2) 客户端传来的明文密码 → SHA-256 哈希（与创建相册时的哈希方式一致）
  v_hashed_input := encode(extensions.digest(input_password::text, 'sha256'::text), 'hex');

  -- 3) 按分享码查相册
  select *
  into v_album
  from public.albums
  where share_code = input_share_code;

  if not found then
    return jsonb_build_object(
      'success', false,
      'error', 'ALBUM_NOT_FOUND',
      'message', '相册不存在，请检查分享码是否正确'
    );
  end if;

  -- 4) 验证密码
  if v_album.password_hash is distinct from v_hashed_input then
    return jsonb_build_object(
      'success', false,
      'error', 'WRONG_PASSWORD',
      'message', '相册密码错误，请重新输入'
    );
  end if;

  -- 5) 验证是否已过期
  if v_album.expires_at is not null 
        and v_album.expires_at < now() 
  then
    return jsonb_build_object(
      'success', false,
      'error', 'ALBUM_EXPIRED',
      'message', '操作失败：该相册已于 '
                || to_char(v_album.expires_at, 'YYYY-MM-DD HH24:MI')
                || ' 过期销毁！'
    );
  end if;

  -- 6) 写入参与关系（创建者不重复写）
  if auth.uid() is not null and auth.uid() <> v_album.creator_id then
    select *
    into v_participant
    from public.album_participants
    where album_id = v_album.id
      and user_id = auth.uid();

    if v_participant is null then
      insert into public.album_participants (album_id, user_id, role, joined_at)
      values (v_album.id, auth.uid(), 'member', now());
    end if;
  end if;

  -- 7) 返回成功
  return jsonb_build_object(
    'success', true,
    'album', jsonb_build_object(
      'id',          v_album.id,
      'name',        v_album.name,
      'share_code',  v_album.share_code,
      'creator_id',  v_album.creator_id,
      'expires_at',  v_album.expires_at,
      'created_at',  v_album.created_at
    )
  );
end;
$$;
