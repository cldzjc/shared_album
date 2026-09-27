import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Android / iOS 平台下载实现：本地沙盒保存 + Gal 写入系统相册。
/// 与改造前的 PhotoDownloadService 行为完全一致。

const Duration _connectTimeout = Duration(seconds: 20);
const Duration _readTimeout = Duration(seconds: 30);

void _log(String message) {
  debugPrint('[PhotoDownloadService] $message');
}

void _logException(String type, Object error, StackTrace stackTrace) {
  debugPrint('[PhotoDownloadService] 异常类型: $type');
  debugPrint('[PhotoDownloadService] 异常信息: $error');
  debugPrint('[PhotoDownloadService] StackTrace:\n$stackTrace');
}

Future<void> _saveToSystemGallery({required String filePath}) async {
  _log('开始保存到系统相册');

  final file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('本地文件不存在，无法保存到系统相册', filePath);
  }

  try {
    await Gal.putImage(filePath);
    _log('系统相册保存成功');
  } on MissingPluginException catch (error, stackTrace) {
    _logException('GalleryPluginMissing', error, stackTrace);
    _log('gal 原生插件未注册。请执行完整重启/重新安装应用后再试。');
  } catch (error, stackTrace) {
    _logException('GallerySaveFailed', error, stackTrace);
    _log('保存到系统相册失败，但本地沙盒文件已保留');
  }
}

/// 下载照片文件到本地
/// 返回文件路径 (成功) 或 null (失败)
Future<String?> downloadPhoto({
  required String fileUrl,
  required String fileName,
  void Function(double progress)? onProgress,
}) async {
  final client = http.Client();
  IOSink? sink;
  var sinkClosed = false;

  try {
    _log('下载开始');
    _log('fileUrl: $fileUrl');
    _log('fileName: $fileName');

    // 1. 获取应用缓存目录
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String photoDir = '${appDir.path}/shared_album_photos';

    // 2. 创建目录（如果不存在）
    final Directory dir = Directory(photoDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 3. 生成本地文件路径
    final String filePath = '$photoDir/$fileName';
    _log('本地保存路径: $filePath');

    // 已下载则直接返回，避免重复拉取
    final File existingFile = File(filePath);
    if (await existingFile.exists()) {
      _log('本地文件已存在，直接复用');
      onProgress?.call(1.0);
      await _saveToSystemGallery(filePath: filePath);
      return filePath;
    }

    // 4. 流式下载文件并回传进度
    final uri = Uri.parse(fileUrl);
    final request = http.Request('GET', Uri.parse(fileUrl));
    request.headers['Accept'] = '*/*';
    request.headers['Connection'] = 'close';
    _log('Request 创建完成');
    _log('开始发送 HTTP 请求');

    final response = await client
        .send(request)
        .timeout(
          _connectTimeout,
          onTimeout: () {
            throw TimeoutException('连接 OSS 超时（${_connectTimeout.inSeconds} 秒）');
          },
        );

    _log('HTTP 请求已返回');
    _log('HTTP StatusCode: ${response.statusCode}');
    _log('Content-Length: ${response.contentLength}');

    if (response.statusCode != 200) {
      throw HttpException('下载失败: HTTP ${response.statusCode}', uri: uri);
    }

    // 5. 保存到本地
    final File file = File(filePath);
    _log('开始写入文件');
    sink = file.openWrite();
    final totalBytes = response.contentLength;
    var receivedBytes = 0;
    var nextProgressLog = 10;

    final stream = response.stream.timeout(
      _readTimeout,
      onTimeout: (EventSink<List<int>> sink) {
        sink.addError(
          TimeoutException('读取 OSS 数据超时（${_readTimeout.inSeconds} 秒）'),
        );
      },
    );

    await for (final chunk in stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;

      if (totalBytes != null && totalBytes > 0) {
        final progress = receivedBytes / totalBytes;
        onProgress?.call(progress);

        final progressPercent = (progress * 100).floor();
        while (nextProgressLog <= 100 && progressPercent >= nextProgressLog) {
          _log('下载进度：$nextProgressLog%');
          nextProgressLog += 10;
        }
      }
    }

    _log('Flush 完成');
    await sink.flush();
    _log('Close 完成');
    await sink.close();
    sinkClosed = true;
    onProgress?.call(1.0);

    _log('下载成功');

    await _saveToSystemGallery(filePath: filePath);

    return filePath;
  } on SocketException catch (error, stackTrace) {
    _logException('SocketException', error, stackTrace);
    throw Exception('连接网络失败: $error');
  } on TimeoutException catch (error, stackTrace) {
    _logException('TimeoutException', error, stackTrace);
    throw Exception(error.message ?? '下载超时');
  } on HttpException catch (error, stackTrace) {
    _logException('HttpException', error, stackTrace);
    throw Exception(error.message);
  } on FileSystemException catch (error, stackTrace) {
    _logException('FileSystemException', error, stackTrace);
    throw Exception('文件保存失败: $error');
  } on Exception catch (error, stackTrace) {
    _logException('Exception', error, stackTrace);
    throw Exception('照片下载失败: $error');
  } catch (error, stackTrace) {
    _logException('Unknown', error, stackTrace);
    throw Exception('照片下载失败: $error');
  } finally {
    if (sink != null && !sinkClosed) {
      try {
        _log('开始关闭文件流（finally）');
        await sink.close();
        _log('文件流关闭完成（finally）');
      } catch (error, stackTrace) {
        _logException('CloseFileStreamError', error, stackTrace);
      }
    }
    client.close();
  }
}

/// 获取应用照片存储目录
Future<String> getPhotosDirectory() async {
  final Directory appDir = await getApplicationDocumentsDirectory();
  return '${appDir.path}/shared_album_photos';
}

/// 检查照片是否已下载
Future<bool> isPhotoDownloaded({required String fileName}) async {
  try {
    final dir = await getPhotosDirectory();
    final file = File('$dir/$fileName');
    return await file.exists();
  } catch (_) {
    return false;
  }
}

/// 获取本地照片文件
Future<File?> getLocalPhotoFile({required String fileName}) async {
  try {
    final dir = await getPhotosDirectory();
    final file = File('$dir/$fileName');
    if (await file.exists()) {
      return file;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 删除本地照片缓存
Future<void> deleteLocalPhoto({required String fileName}) async {
  try {
    final file = await getLocalPhotoFile(fileName: fileName);
    if (file != null) {
      await file.delete();
    }
  } catch (_) {
    // 忽略删除失败
  }
}
