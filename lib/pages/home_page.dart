
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'patch_page.dart';
import 'source_viewer_page.dart';
import 'tools_page.dart';

enum _LogType { info, ok, err, warn }

class _Log {
  final String time;
  final String text;
  final _LogType type;
  _Log(this.text, this.type)
      : time = DateTime.now().toString().substring(11, 19);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = ApiService();
  final _logCtrl = ScrollController();
  final _logs = <_Log>[];

  Uint8List? _apkBytes;
  String? _apkName;
  ApkInfo? _apkInfo;
  Uint8List? _libSoBytes;
  bool _useNativeSo = false;
  Map<String, String> _patchParams = {};
  DecryptResult? _result;
  bool _busy = false;
  String _stage = '';

  @override
  void initState() {
    super.initState();
    _log('iAppDecoder 就绪。请选择要解析的 APK 文件。', _LogType.info);
  }

  void _log(String text, _LogType type) {
    setState(() => _logs.add(_Log(text, type)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logCtrl.hasClients) {
        _logCtrl.jumpTo(_logCtrl.position.maxScrollExtent);
      }
    });
  }

  Color _logColor(_LogType t) {
    switch (t) {
      case _LogType.ok:
        return const Color(0xFF3FB950);
      case _LogType.err:
        return const Color(0xFFF85149);
      case _LogType.warn:
        return const Color(0xFFD29922);
      case _LogType.info:
        return const Color(0xFF8B949E);
    }
  }

  Future<void> _pickApk() async {
    final res = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    if (res == null) return;
    final bytes = await res.readAsBytes();
    _restart(silent: true);
    setState(() {
      _apkBytes = bytes;
      _apkName = res.name;
    });
    _log('已选择 APK: $_apkName (${_apkBytes!.length} 字节)', _LogType.ok);
    await _runParse();
  }

  Future<void> _runParse() async {
    if (_apkBytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      _stage = 'extract_apk';
      _log('正在解析 APK 结构并上传...', _LogType.info);
      final info = await _api.extractApk(
        _apkBytes!,
        _apkName!,
        onProgress: (p) => _log(
          '上传分片 ${p.chunkIndex}/${p.chunkCount}',
          _LogType.info,
        ),
      );
      setState(() {
        _apkInfo = info;
        _libSoBytes = info.libSoBytes;
      });
      _log('包名: ${info.packageName}', _LogType.ok);
      _log('应用名: ${info.appName}  版本: ${info.versionName}(${info.versionCode})', _LogType.ok);
      _log('检测模式: ${info.detectedMode}', _LogType.info);
      _log('dek: ${info.dek ?? '(未提供)'}', _LogType.info);
      if (info.sok != null && info.sok!.isNotEmpty) _log('sok: ${info.sok}', _LogType.info);
      if (info.nativeSoBytes == null) {
        _log('未发现原生 so，SO 功能不可用', _LogType.warn);
      }

      if (_libSoBytes == null) {
        _log('APK 内未找到 lib.so，无法解密', _LogType.err);
        return;
      }

      final sha = sha256.convert(_libSoBytes!).toString();
      _log('lib.so sha256: $sha', _LogType.info);
      _stage = 'cache_lookup';
      final cached = await _api.cacheLookup(sha);
      if (cached != null) {
        _log('命中解密缓存，直接返回结果', _LogType.ok);
        setState(() {
          _result = cached;
          _busy = false;
        });
        _openFiles();
        return;
      }
      _log('未命中缓存，开始解密', _LogType.info);
      await _runDecrypt();
    } on ApiException catch (e) {
      _log('[ERR] $e', _LogType.err);
      if (_stage == 'extract_apk') {
        _log('提示: 若 AndroidManifest 解析异常，可使用 P 菜单手动填写参数后重试', _LogType.warn);
      }
    } catch (e) {
      _log('[ERR] 意外错误: $e', _LogType.err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, String> _buildParams() {
    final info = _apkInfo!;
    String pick(String key, String? fallback) {
      final v = _patchParams[key];
      if (v != null && v.isNotEmpty) return v;
      return fallback ?? '';
    }

    final p = <String, String>{
      'package_name': pick('package_name', info.packageName),
      'version_name': pick('version_name', info.versionName),
      'version_code': pick('version_code', info.versionCode),
      'app_name': pick('app_name', info.appName),
      'dek': pick('dek', info.dek),
      'mode': pick('mode', info.detectedMode),
      'entry_file': pick('entry_file', 'mian.iyu'),
    };
    for (final k in ['sok', 'sign_key', 'sign_b64', 'pwd_key', 'post_key', 'xor_key']) {
      final v = pick(k, k == 'sok' ? info.sok : null);
      if (v.isNotEmpty) p[k] = v;
    }
    return p;
  }

  Future<void> _runDecrypt() async {
    if (_libSoBytes == null || _busy) return;
    final params = _buildParams();
    if ((params['dek'] ?? '').isEmpty) {
      _log('缺少 dek 密钥，请使用 P 菜单手动填写后重试', _LogType.err);
      return;
    }
    setState(() => _busy = true);
    try {
      Uint8List? nativeBytes;
      if (_useNativeSo && _apkInfo?.nativeSoBytes != null) {
        nativeBytes = _apkInfo!.nativeSoBytes;
        _log('[实验性] 已附加原生 so: ${_apkInfo!.nativeSoName}', _LogType.warn);
      }
      _stage = 'decrypt';
      final r = await _api.decrypt(
        libSoBytes: _libSoBytes!,
        libSoName: _apkInfo?.libSoName ?? 'lib.so',
        nativeSoBytes: nativeBytes,
        nativeSoName: _apkInfo?.nativeSoName ?? 'native.so',
        params: params,
      );
      setState(() => _result = r);
      _log('${r.message}${r.cacheHit ? '（缓存命中）' : ''}', _LogType.ok);
      _log('算法族: ${r.strategy['algorithm_family'] ?? '-'}  尝试候选: ${r.strategy['tried_count'] ?? '-'}', _LogType.info);
      _log('解密成功 ${r.files.length} 个文件，失败 ${r.failed.length} 个', _LogType.ok);
      for (final f in r.failed) {
        _log('失败: ${f.name} (${f.error})', _LogType.warn);
      }
      _openFiles();
    } on ApiException catch (e) {
      _log('[ERR] $e', _LogType.err);
    } catch (e) {
      _log('[ERR] 意外错误: $e', _LogType.err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restart({bool silent = false}) {
    setState(() {
      _apkBytes = null;
      _apkName = null;
      _apkInfo = null;
      _libSoBytes = null;
      _useNativeSo = false;
      _patchParams = {};
      _result = null;
      _busy = false;
      _stage = '';
    });
    if (!silent) _log('R: 任务已重置，请重新选择 APK', _LogType.warn);
  }

  Future<void> _openPatch() async {
    final initial = <String, String>{
      if (_apkInfo != null) ...{
        'package_name': _apkInfo!.packageName,
        'version_name': _apkInfo!.versionName,
        'version_code': _apkInfo!.versionCode,
        'app_name': _apkInfo!.appName,
        'dek': _apkInfo!.dek ?? '',
        'sok': _apkInfo!.sok ?? '',
        'sign_key': _apkInfo!.signKey ?? '',
        'sign_b64': _apkInfo!.signB64 ?? '',
        'mode': _apkInfo!.detectedMode,
      },
      ..._patchParams,
    };
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => PatchPage(initial: initial)),
    );
    if (result == null) return;
    setState(() => _patchParams = result);
    _log('P: 已应用手动参数，正在重新解析...', _LogType.warn);
    if (_apkBytes != null) await _runParse();
  }

  void _openFiles() {
    final r = _result;
    if (r == null) return;
    if (r.files.isEmpty) {
      _log('没有解密成功的文件', _LogType.err);
      return;
    }
    if (r.files.length == 1) {
      final name = r.files.keys.first;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => SourceViewerPage(fileName: name, content: r.files[name]!),
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('解密结果 (${r.files.length} 个文件)', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...r.files.entries.map((e) => ListTile(
                  leading: const Icon(Icons.description_outlined, color: Color(0xFF58A6FF)),
                  title: Text(e.key, style: const TextStyle(fontFamily: 'monospace')),
                  subtitle: Text('${e.value.length} 字符', style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SourceViewerPage(fileName: e.key, content: e.value),
                    ));
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _openSearch() {
    final r = _result;
    if (r == null || r.files.isEmpty) {
      _log('S: 当前没有可搜索的解密结果', _LogType.warn);
      return;
    }
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setD) {
        final hits = r.files.keys
            .where((k) => ctrl.text.isEmpty || k.toLowerCase().contains(ctrl.text.toLowerCase()))
            .toList();
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('S: 查找源码文件'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '输入文件名关键字', isDense: true),
                  onChanged: (_) => setD(() {}),
                ),
                const SizedBox(height: 12),
                ...hits.take(8).map((k) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.code, size: 18),
                      title: Text(k, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => SourceViewerPage(fileName: k, content: r.files[k]!),
                        ));
                      },
                    )),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        );
      });
    });
  }

  Widget _menuBtn(String label, String tip, VoidCallback onTap, {bool active = false}) {
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: _busy ? null : onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF1F6FEB) : const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _busy ? const Color(0xFF484F58) : (active ? Colors.white : const Color(0xFF58A6FF)),
            )),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _apkInfo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('iAppDecoder', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(tooltip: '实验功能', icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsPage()))),
          IconButton(tooltip: '选择 APK', icon: const Icon(Icons.folder_open), onPressed: _busy ? null : _pickApk),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            width: double.infinity,
            color: const Color(0xFF161B22),
            child: Row(
              children: [
                _menuBtn('R', 'Restart: 重启任务', () => _restart()),
                _menuBtn('P', 'Patch: 手动填写参数', _openPatch),
                _menuBtn('S', 'Search: 查找源码文件', _openSearch),
                _menuBtn('W', 'Write: 重写源码', _openFiles),
                _menuBtn('SO', '实验性: 附加原生 so 解密', () {
                  setState(() => _useNativeSo = !_useNativeSo);
                  _log('SO: ${_useNativeSo ? '已开启' : '已关闭'}原生 so 附加', _LogType.warn);
                }, active: _useNativeSo),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy ? null : (_apkBytes == null ? _pickApk : _runDecrypt),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(_apkBytes == null ? '选择 APK' : '重新解密'),
                ),
              ],
            ),
          ),
          if (_busy)
            const LinearProgressIndicator(minHeight: 2, backgroundColor: Color(0xFF21262D)),
          if (info != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: const Color(0xFF0D1117),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _chip('应用', info.appName),
                  _chip('包名', info.packageName),
                  _chip('版本', '${info.versionName}(${info.versionCode})'),
                  _chip('模式', info.detectedMode),
                  if (_patchParams.isNotEmpty) _chip('Patch', '${_patchParams.length} 项覆盖', highlight: true),
                ],
              ),
            ),
          Expanded(
            child: Container(
              color: const Color(0xFF010409),
              child: ListView.builder(
                controller: _logCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: _logs.length,
                itemBuilder: (_, i) {
                  final l = _logs[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '[${l.time}] ', style: TextStyle(color: _logColor(l.type).withValues(alpha: 0.6))),
                      TextSpan(text: l.text, style: TextStyle(color: _logColor(l.type))),
                    ], style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String k, String v, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF3D2E00) : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Text('$k: $v', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
    );
  }
}
