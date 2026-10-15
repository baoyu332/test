
import 'dart:convert';
import 'dart:typed_data';

class ApkInfo {
  final String packageName;
  final String versionName;
  final String versionCode;
  final String appName;
  final String? sok;
  final String? dek;
  final String? signKey;
  final String? signB64;
  final String detectedMode;
  final Uint8List? libSoBytes;
  final String libSoName;
  final Uint8List? nativeSoBytes;
  final String nativeSoName;

  ApkInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.appName,
    this.sok,
    this.dek,
    this.signKey,
    this.signB64,
    this.detectedMode = 'current',
    this.libSoBytes,
    this.libSoName = 'lib.so',
    this.nativeSoBytes,
    this.nativeSoName = '',
  });

  factory ApkInfo.fromJson(Map<String, dynamic> j) {
    Uint8List? dec(String key) {
      final v = j[key];
      if (v is! String || v.isEmpty) return null;
      try {
        return base64Decode(v);
      } catch (_) {
        return null;
      }
    }

    return ApkInfo(
      packageName: (j['package_name'] ?? '') as String,
      versionName: (j['version_name'] ?? '') as String,
      versionCode: (j['version_code'] ?? '') as String,
      appName: (j['app_name'] ?? '') as String,
      sok: j['sok'] as String?,
      dek: j['dek'] as String?,
      signKey: j['sign_key'] as String?,
      signB64: j['sign_b64'] as String?,
      detectedMode: (j['detected_mode'] ?? 'current') as String,
      libSoBytes: dec('lib_so_base64'),
      libSoName: (j['lib_so_name'] ?? 'lib.so') as String,
      nativeSoBytes: dec('native_so_base64'),
      nativeSoName: (j['native_so_name'] ?? '') as String,
    );
  }
}

class FailedFile {
  final String name;
  final String error;

  FailedFile({required this.name, required this.error});

  factory FailedFile.fromJson(dynamic j) =>
      FailedFile(name: j['name']?.toString() ?? '?', error: j['error']?.toString() ?? '');
}

class DecryptResult {
  final String entryFile;
  final Map<String, String> files;
  final List<FailedFile> failed;
  final Map<String, dynamic> strategy;
  final bool cacheHit;
  final String message;

  DecryptResult({
    required this.entryFile,
    required this.files,
    required this.failed,
    required this.strategy,
    required this.cacheHit,
    required this.message,
  });

  factory DecryptResult.fromJson(Map<String, dynamic> j) {
    final files = <String, String>{};
    final rawFiles = j['files'];
    if (rawFiles is Map) {
      rawFiles.forEach((k, v) => files[k.toString()] = v?.toString() ?? '');
    }
    final failed =
        (j['failed'] as List? ?? []).map((e) => FailedFile.fromJson(e)).toList();
    return DecryptResult(
      entryFile: (j['entry_file'] ?? '') as String,
      files: files,
      failed: failed,
      strategy: (j['strategy'] as Map?)?.cast<String, dynamic>() ?? const {},
      cacheHit: j['cache_hit'] == true,
      message: (j['message'] ?? '') as String,
    );
  }
}

class LibKeyItem {
  final String path;
  final String postKey;
  final String xorKey;

  LibKeyItem({required this.path, required this.postKey, required this.xorKey});

  factory LibKeyItem.fromJson(dynamic j) => LibKeyItem(
        path: j['path']?.toString() ?? '',
        postKey: j['post_key']?.toString() ?? '',
        xorKey: j['xor_key']?.toString() ?? '',
      );
}

class RepairResult {
  final String message;
  final int dexCount;
  final int mappingCount;
  final int modifiedFileCount;
  final int replacedCount;
  final List<String> modifiedFiles;
  final String downloadUrl;
  final String zipName;

  RepairResult({
    required this.message,
    required this.dexCount,
    required this.mappingCount,
    required this.modifiedFileCount,
    required this.replacedCount,
    required this.modifiedFiles,
    required this.downloadUrl,
    required this.zipName,
  });

  factory RepairResult.fromJson(Map<String, dynamic> j) => RepairResult(
        message: (j['message'] ?? '') as String,
        dexCount: (j['dex_count'] as num?)?.toInt() ?? 0,
        mappingCount: (j['mapping_count'] as num?)?.toInt() ?? 0,
        modifiedFileCount: (j['modified_file_count'] as num?)?.toInt() ?? 0,
        replacedCount: (j['replaced_count'] as num?)?.toInt() ?? 0,
        modifiedFiles:
            (j['modified_files'] as List? ?? []).map((e) => e.toString()).toList(),
        downloadUrl: (j['download_url'] ?? '') as String,
        zipName: (j['zip_name'] ?? 'source_repaired.zip') as String,
      );
}