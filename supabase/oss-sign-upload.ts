// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

async function hmacSha1(key: string, data: string) {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    enc.encode(key),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'HMAC',
    cryptoKey,
    enc.encode(data),
  );
  return btoa(String.fromCharCode(...new Uint8Array(signature)));
}

function inferExt(filename: string, contentType: string) {
  const pos = filename.lastIndexOf('.');
  if (pos !== -1) return filename.substring(pos).toLowerCase();
  if (contentType === 'image/png') return '.png';
  if (contentType === 'image/webp') return '.webp';
  if (contentType === 'image/gif') return '.gif';
  if (contentType === 'image/heic') return '.heic';
  return '.jpg';
}

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

serve(async (req) => {
  // Web 浏览器 CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      status: 200,
      headers: corsHeaders,
    });
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', {
      status: 405,
      headers: corsHeaders,
    });
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, {
      error: 'Invalid JSON body',
    });
  }

  const { filename, contentType, album_id, uploader_id } = body ?? {};

  if (!filename || !album_id || !uploader_id) {
    return jsonResponse(400, {
      error: 'filename, album_id, uploader_id required',
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authHeader = req.headers.get('Authorization');

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse(500, {
      error: 'Supabase 配置缺失',
    });
  }

  if (!authHeader) {
    return jsonResponse(401, {
      error: '未登录，无法申请上传地址',
    });
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const { data: userResult, error: userError } =
    await authClient.auth.getUser();

  if (userError || !userResult.user) {
    return jsonResponse(401, {
      error: '登录已失效，请重新登录后再试',
    });
  }

  if (userResult.user.id !== uploader_id) {
    return jsonResponse(403, {
      error: 'uploader_id 与当前登录用户不一致',
    });
  }

  const adminClient = createClient(
    supabaseUrl,
    serviceRoleKey,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    },
  );

  const { data: albumRow, error: albumError } =
    await adminClient
      .from('albums')
      .select('id, creator_id')
      .eq('id', album_id)
      .maybeSingle();

  if (albumError) {
    return jsonResponse(500, {
      error: `查询相册失败: ${albumError.message}`,
    });
  }

  if (!albumRow) {
    return jsonResponse(404, {
      error: '相册不存在',
    });
  }

  if (albumRow.creator_id !== userResult.user.id) {
    const {
      data: participantRow,
      error: participantError,
    } = await adminClient
      .from('album_participants')
      .select('album_id')
      .eq('album_id', album_id)
      .eq('user_id', userResult.user.id)
      .maybeSingle();

    if (participantError) {
      return jsonResponse(500, {
        error: `查询参与关系失败: ${participantError.message}`,
      });
    }

    if (!participantRow) {
      return jsonResponse(403, {
        error: '你没有权限上传到这个相册',
      });
    }
  }

  // ── 免费版上限校验：相册最多 200 张照片 ──
  // 与 Flutter 端 lib/config/app_config.dart 的 maxPhotosPerFreeAlbum 保持一致；
  // 调整上限时需同步修改两端，避免前后端上限不一致。
  const MAX_PHOTOS_PER_FREE_ALBUM = 200;

  const { count: existingCount, error: countError } =
    await adminClient
      .from('photos')
      .select('id', { count: 'exact', head: true })
      .eq('album_id', album_id);

  if (countError) {
    return jsonResponse(500, {
      error: `查询相册照片数失败: ${countError.message}`,
    });
  }

  if ((existingCount ?? 0) >= MAX_PHOTOS_PER_FREE_ALBUM) {
    return jsonResponse(400, {
      error: `该相册已达到免费版 ${MAX_PHOTOS_PER_FREE_ALBUM} 张照片上限，无法继续上传`,
    });
  }

  const accessKeyId =
    Deno.env.get('OSS_ACCESS_KEY_ID')!;
  const accessKeySecret =
    Deno.env.get('OSS_ACCESS_KEY_SECRET')!;
  const bucket =
    Deno.env.get('OSS_BUCKET')!;
  const region =
    Deno.env.get('OSS_REGION')!;

  const timestamp = Date.now();
  const ext = inferExt(
    String(filename),
    String(contentType || 'image/jpeg'),
  );

  const objectKey =
    `shared_album/${album_id}/${uploader_id}/${timestamp}${ext}`;

  const expires =
    Math.floor(Date.now() / 1000) + 60;

  const canonicalString =
    `PUT\n\n${contentType || 'image/jpeg'}\n${expires}\n/${bucket}/${objectKey}`;

  const signature =
    await hmacSha1(
      accessKeySecret,
      canonicalString,
    );

  const uploadUrl =
    `https://${bucket}.${region}.aliyuncs.com/${objectKey}` +
    `?OSSAccessKeyId=${accessKeyId}` +
    `&Expires=${expires}` +
    `&Signature=${encodeURIComponent(signature)}`;

  const publicUrl =
    `https://${bucket}.${region}.aliyuncs.com/${objectKey}`;

  return new Response(
    JSON.stringify({
      uploadUrl,
      publicUrl,
      objectKey,
      expires,
    }),
    {
      status: 200,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
      },
    },
  );
});
