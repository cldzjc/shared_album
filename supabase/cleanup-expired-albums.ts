// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

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

async function deleteOssObject(params: {
  accessKeyId: string;
  accessKeySecret: string;
  bucket: string;
  region: string;
  objectKey: string;
}) {
  const cleanKey = params.objectKey.replace(/^\/+/, '');
  const encodedKey = cleanKey
    .split('/')
    .map((part) => encodeURIComponent(part))
    .join('/');

  const date = new Date().toUTCString();
  const canonicalResource = `/${params.bucket}/${cleanKey}`;
  const stringToSign = `DELETE\n\n\n${date}\n${canonicalResource}`;
  const signature = await hmacSha1Base64(params.accessKeySecret, stringToSign);

  const response = await fetch(
    `https://${params.bucket}.${params.region}.aliyuncs.com/${encodedKey}`,
    {
      method: 'DELETE',
      headers: {
        Date: date,
        Authorization: `OSS ${params.accessKeyId}:${signature}`,
      },
    },
  );

  if (response.status === 404) {
    return;
  }

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OSS 删除失败: HTTP ${response.status} ${errorText}`);
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST' && req.method !== 'GET') {
    return jsonResponse(405, { success: false, message: 'Method not allowed' });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  const accessKeyId = Deno.env.get('OSS_ACCESS_KEY_ID');
  const accessKeySecret = Deno.env.get('OSS_ACCESS_KEY_SECRET');
  const bucket = Deno.env.get('OSS_BUCKET');
  const region = Deno.env.get('OSS_REGION');

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(500, { success: false, message: 'Supabase 配置缺失' });
  }

  if (!accessKeyId || !accessKeySecret || !bucket || !region) {
    return jsonResponse(500, { success: false, message: 'OSS 配置缺失' });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const nowIso = new Date().toISOString();

  const { data: expiredAlbums, error: expiredAlbumsError } = await adminClient
    .from('albums')
    .select('id, expires_at')
    .lte('expires_at', nowIso)
    .order('expires_at', { ascending: true })
    .limit(20);

  if (expiredAlbumsError) {
    return jsonResponse(500, {
      success: false,
      message: `查询过期相册失败: ${expiredAlbumsError.message}`,
    });
  }

  if (!expiredAlbums || expiredAlbums.length === 0) {
    const summary = {
      success: true,
      message: '没有需要清理的过期相册',
      expiredAlbums: 0,
      deletedPhotos: 0,
      failedAlbums: 0,
      failedPhotos: 0,
      processedAt: nowIso,
      batchLimit: 20,
    };

    console.log('[cleanup-expired-albums] summary', summary);
    return jsonResponse(200, summary);
  }

  let deletedPhotos = 0;
  let failedPhotos = 0;
  let deletedAlbums = 0;
  let failedAlbums = 0;

  for (const album of expiredAlbums) {
    const albumId = String(album.id);
    let albumHasError = false; // 标记当前相册处理过程中是否有照片失败

    const { data: photos, error: photosError } = await adminClient
      .from('photos')
      .select('id, storage_path')
      .eq('album_id', albumId);

    if (photosError) {
      failedAlbums += 1;
      console.error('[cleanup-expired-albums] 查询相册照片失败', {
        albumId,
        error: photosError.message,
      });
      continue;
    }

    for (const photo of photos ?? []) {
      const photoId = String(photo.id);
      const storagePath = String(photo.storage_path ?? '').trim();

      if (!storagePath) {
        failedPhotos += 1;
        albumHasError = true;
        console.error('[cleanup-expired-albums] storage_path 为空，跳过该照片', {
          albumId,
          photoId,
        });
        continue;
      }

      try {
        await deleteOssObject({
          accessKeyId,
          accessKeySecret,
          bucket,
          region,
          objectKey: storagePath,
        });
      } catch (error) {
        failedPhotos += 1;
        albumHasError = true;
        console.error('[cleanup-expired-albums] 删除 OSS 失败', {
          albumId,
          photoId,
          storagePath,
          error: error instanceof Error ? error.message : String(error),
        });
        continue;
      }

      const { error: deletePhotoError } = await adminClient
        .from('photos')
        .delete()
        .eq('id', photoId);

      if (deletePhotoError) {
        failedPhotos += 1;
        albumHasError = true;
        console.error('[cleanup-expired-albums] 删除 photos 记录失败', {
          albumId,
          photoId,
          error: deletePhotoError.message,
        });
        continue;
      }

      deletedPhotos += 1;
    }

    // 如果有任何一张照片处理失败，跳过删除当前相册记录
    if (albumHasError) {
      failedAlbums += 1;
      console.warn(
        '[cleanup-expired-albums] 相册存在删除失败的照片，跳过删除 albums 记录',
        {
          albumId,
        },
      );
      continue;
    }

    const { error: deleteAlbumError } = await adminClient
      .from('albums')
      .delete()
      .eq('id', albumId);

    if (deleteAlbumError) {
      failedAlbums += 1;
      console.error('[cleanup-expired-albums] 删除 albums 记录失败', {
        albumId,
        error: deleteAlbumError.message,
      });
      continue;
    }

    deletedAlbums += 1;
  }

  const summary = {
    success: true,
    message: '过期相册清理完成',
    expiredAlbums: deletedAlbums,
    deletedPhotos,
    failedAlbums,
    failedPhotos,
    processedAlbums: expiredAlbums.length,
    processedAt: new Date().toISOString(),
    batchLimit: 20,
  };

  console.log('[cleanup-expired-albums] summary', summary);

  return jsonResponse(200, summary);
});