// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

type ResourceType = 'photo' | 'album';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
    },
  });
}

async function hmacSha1Base64(secret: string, data: string) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(data));
  return btoa(String.fromCharCode(...new Uint8Array(signature)));
}

async function deleteOssObject(objectKey: string) {
  const accessKeyId = Deno.env.get('OSS_ACCESS_KEY_ID');
  const accessKeySecret = Deno.env.get('OSS_ACCESS_KEY_SECRET');
  const bucket = Deno.env.get('OSS_BUCKET');
  const region = Deno.env.get('OSS_REGION');

  if (!accessKeyId || !accessKeySecret || !bucket || !region) {
    throw new Error('OSS 配置缺失');
  }

  const cleanKey = objectKey.replace(/^\/+/, '');
  const encodedKey = cleanKey.split('/').map((part) => encodeURIComponent(part)).join('/');
  const date = new Date().toUTCString();
  
  // 核心修复：补全反引号
  const canonicalResource = `/${bucket}/${cleanKey}`;
  const stringToSign = `DELETE\n\n\n${date}\n${canonicalResource}`;
  const signature = await hmacSha1Base64(accessKeySecret, stringToSign);

  // 核心修复：补全反引号
  const response = await fetch(`https://${bucket}.${region}.aliyuncs.com/${encodedKey}`, {
    method: 'DELETE',
    headers: {
      Date: date,
      Authorization: `OSS ${accessKeyId}:${signature}`,
    },
  });

  if (!response.ok) {
    const errorText = await response.text();
    // 核心修复：补全反引号
    throw new Error(`OSS 删除失败: HTTP ${response.status} ${errorText}`);
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse(405, { success: false, message: 'Method not allowed' });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { success: false, message: 'Invalid JSON body' });
  }

  const resourceType = String(body.resourceType ?? body.type ?? '').trim() as ResourceType;
  const photoId = String(body.photoId ?? '').trim();

  if (!resourceType || !photoId) {
    return jsonResponse(400, {
      success: false,
      message: 'resourceType 和 photoId 为必填项',
    });
  }

  if (resourceType !== 'photo') {
    return jsonResponse(400, {
      success: false,
      // 核心修复：补全反引号
      message: `当前仅支持 resourceType=photo，收到的是 ${resourceType}`,
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authHeader = req.headers.get('Authorization');

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse(500, { success: false, message: 'Supabase 配置缺失' });
  }

  if (!authHeader) {
    return jsonResponse(401, { success: false, message: '未登录，无法删除照片' });
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

  const { data: userResult, error: userError } = await authClient.auth.getUser();
  if (userError || !userResult.user) {
    return jsonResponse(401, { success: false, message: '登录已失效，请重新登录后再试' });
  }

  const userId = userResult.user.id;
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const { data: photoRow, error: photoError } = await adminClient
    .from('photos')
    .select('id, album_id, storage_path, uploader_id')
    .eq('id', photoId)
    .maybeSingle();

  if (photoError) {
    // 核心修复：补全反引号
    return jsonResponse(500, { success: false, message: `查询照片失败: ${photoError.message}` });
  }

  if (!photoRow) {
    return jsonResponse(404, { success: false, message: '照片不存在或已经删除' });
  }

  const { data: albumRow, error: albumError } = await adminClient
    .from('albums')
    .select('id, creator_id')
    .eq('id', photoRow.album_id)
    .maybeSingle();

  if (albumError) {
    // 核心修复：补全反引号
    return jsonResponse(500, { success: false, message: `查询相册失败: ${albumError.message}` });
  }

  if (!albumRow) {
    return jsonResponse(404, { success: false, message: '照片所属相册不存在' });
  }

  const uploaderId = photoRow.uploader_id as string | null;
  const creatorId = albumRow.creator_id as string;
  const hasPermission = userId === uploaderId || userId === creatorId;

  if (!hasPermission) {
    return jsonResponse(403, { success: false, message: '没有删除该照片的权限' });
  }

  const storagePath = String(photoRow.storage_path ?? '').trim();
  if (!storagePath) {
    return jsonResponse(500, { success: false, message: '照片缺少 storage_path，无法删除 OSS 原图' });
  }

  try {
    await deleteOssObject(storagePath);
  } catch (error) {
    return jsonResponse(502, {
      success: false,
      message: error instanceof Error ? error.message : 'OSS 删除失败',
    });
  }

  const { error: deleteError } = await adminClient.from('photos').delete().eq('id', photoId);
  if (deleteError) {
    return jsonResponse(500, {
      success: false,
      // 核心修复：补全反引号
      message: `OSS 已删除，但数据库记录删除失败: ${deleteError.message}`,
    });
  }

  return jsonResponse(200, {
    success: true,
    message: '照片删除成功',
    resourceType,
    photoId,
  });
});