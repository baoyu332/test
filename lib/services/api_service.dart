
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class UploadProgress {
  final int sent;
  final int total;
  final int chunkIndex;
  final int chunkCount;

  UploadProgress({
    required this.sent,
    required this.total,
    required this.chunkIndex,
    required this.chunkCount,
  });
}

class ApiService {
  static const String baseUrl = 'https://iapp.0d0d.top';
  final http.Client _client = http.Client();

  Map<String, dynamic> _check(http.Response resp, String what) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('$what失败: HTTP ${resp.statusCode} 响应异常');
    }
    if (resp.statusCode != 200 || body['ok'] != true) {
      throw ApiException('$what失败: ${body['error'] ?? body['message'] ?? 'HTTP ${resp.statusCode}'}');
    }
    return body;
  }

  Future<String> uploadFile(
    Uint8List bytes,
    String filename,
    String purpose, {
    void Function(UploadProgress p)? onProgress,
  }) async {
    final init = _check(
      await _client.post(
        Uri.parse('$baseUrl/upload_init'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'filename': filename, 'size': bytes.length, 'purpose': purpose}),
      ),
      '创建上传会话',
    );
    final uploadId = init['upload_id'] as String;
    final chunkSize = (init['chunk_size'] as num?)?.toInt() ?? 2097152;
    final chunkCount = bytes.isEmpty ? 0 : (bytes.length + chunkSize - 1) ~/ chunkSize;
    for (var i = 0; i < chunkCount; i++) {
      final start = i * chunkSize;
      final end = math.min(start + chunkSize, bytes.length);
      await _client.post(
        Uri.parse('$baseUrl/upload_chunk?upload_id=$uploadId&index=$i'),
        headers: const {'Content-Type': 'application/octet-stream'},
        body: Uint8List.sublistView(bytes, start, end),
      );
      onProgress?.call(UploadProgress(
        sent: end,
        total: bytes.length,
        chunkIndex: i + 1,
        chunkCount: chunkCount,
      ));
    }
    final done = _check(
      await _client.post(
        Uri.parse('$baseUrl/upload_complete'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'upload_id': uploadId}),
      ),
      '完成上传',
    );
    return done['file_token'] as String;
  }

  Future<ApkInfo> extractApk(
    Uint8List apkBytes,
    String filename, {
    void Function(UploadProgress p)? onProgress,
  }) async {
    final token = await uploadFile(apkBytes, filename, 'extract_apk', onProgress: onProgress);
    final body = _check(
      await _client.post(
        Uri.parse('$baseUrl/extract_apk'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'apk_token': token}),
      ),
      '提取 APK 参数',
    );
    return ApkInfo.fromJson((body['data'] as Map).cast<String, dynamic>());
  }

  Future<DecryptResult> decrypt({
    required Uint8List libSoBytes,
    String libSoName = 'lib.so',
    Uint8List? nativeSoBytes,
    String nativeSoName = 'native.so',
    required Map<String, String> params,
    void Function(UploadProgress p)? onProgress,
  }) async {
    final libToken = await uploadFile(libSoBytes, libSoName, 'decrypt_libso', onProgress: onProgress);
    String? nativeToken;
    if (nativeSoBytes != null && nativeSoBytes.isNotEmpty) {
      nativeToken = await uploadFile(nativeSoBytes, nativeSoName, 'decrypt_native_so', onProgress: onProgress);
    }
    final body = <String, dynamic>{
      'libso_token': libToken,
      'format': 'json',
      ...params,
    };
    if (nativeToken != null) body['native_so_token'] = nativeToken;
    final resp = _check(
      await _client.post(
        Uri.parse('$baseUrl/decrypt'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
      '解密源码',
    );
    return DecryptResult.fromJson(resp);
  }

  Future<List<LibKeyItem>> extractLibs(
    Uint8List zipBytes,
    String filename, {
    void Function(UploadProgress p)? onProgress,
  }) async {
    final token = await uploadFile(zipBytes, filename, 'extract_libs', onProgress: onProgress);
    final body = _check(
      await _client.post(
        Uri.parse('$baseUrl/extract_libs'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'libzip_token': token}),
      ),
      '提取动态库 Key',
    );
    return (body['items'] as List? ?? []).map(LibKeyItem.fromJson).toList();
  }

  Future<RepairResult> repairDynamic(
    Uint8List dexZip,
    String dexName,
    Uint8List srcZip,
    String srcName, {
    void Function(UploadProgress p)? onProgress,
  }) async {
    final dexToken = await uploadFile(dexZip, dexName, 'repair_dynamic_dexzip', onProgress: onProgress);
    final srcToken = await uploadFile(srcZip, srcName, 'repair_dynamic_srczip', onProgress: onProgress);
    final body = _check(
      await _client.post(
        Uri.parse('$baseUrl/repair_dynamic'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'dexzip_token': dexToken, 'srczip_token': srcToken}),
      ),
      '动态加密修复',
    );
    return RepairResult.fromJson(body);
  }

  Future<DecryptResult?> cacheLookup(String sha256Hex) async {
    final body = _check(
      await _client.post(
        Uri.parse('$baseUrl/cache_lookup'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'lib_sha256': sha256Hex}),
      ),
      '缓存查询',
    );
    if (body['cache_hit'] == true) return DecryptResult.fromJson(body);
    return null;
  }

  Future<Uint8List> downloadRepair(String downloadUrl) async {
    final path = downloadUrl.startsWith('/') ? downloadUrl : '/$downloadUrl';
    final resp = await _client.get(Uri.parse('$baseUrl$path'));
    if (resp.statusCode != 200) throw ApiException('下载修复结果失败: HTTP ${resp.statusCode}');
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> health() async =>
      _check(await _client.get(Uri.parse('$baseUrl/health')), '健康检查');
}