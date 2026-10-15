
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api_service.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final _api = ApiService();
  bool _busy = false;
  String _status = '';
  List<LibKeyItem> _keys = [];
  RepairResult? _repair;

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<(Uint8List?, String)> _pick(String ext) async {
    final res = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (res == null) return (null, '');
    return (await res.readAsBytes(), res.name);
  }

  Future<void> _extractLibs() async {
    final (bytes, name) = await _pick('zip');
    if (bytes == null) return;
    setState(() { _busy = true; _status = '正在上传并提取动态库 Key...'; });
    try {
      final items = await _api.extractLibs(bytes, name);
      setState(() => _keys = items);
      _toast('提取到 ${items.length} 个动态库的 Key');
    } catch (e) {
      _toast('提取失败: $e');
    } finally {
      if (mounted) setState(() { _busy = false; _status = ''; });
    }
  }

  Future<void> _runRepair() async {
    final (dex, dexName) = await _pick('zip');
    if (dex == null) return;
    final (src, srcName) = await _pick('zip');
    if (src == null) return;
    setState(() { _busy = true; _status = '正在上传并修复动态加密源码...'; });
    try {
      final r = await _api.repairDynamic(dex, dexName, src, srcName);
      setState(() => _repair = r);
      _toast(r.message);
    } catch (e) {
      _toast('修复失败: $e');
    } finally {
      if (mounted) setState(() { _busy = false; _status = ''; });
    }
  }

  Future<void> _downloadRepair() async {
    final r = _repair;
    if (r == null) return;
    setState(() { _busy = true; _status = '正在下载修复结果...'; });
    try {
      final bytes = await _api.downloadRepair(r.downloadUrl);
      final x = XFile.fromData(bytes, mimeType: 'application/zip', name: r.zipName);
      await SharePlus.instance.share(ShareParams(files: [x], text: r.zipName));
    } catch (e) {
      _toast('下载失败: $e');
    } finally {
      if (mounted) setState(() { _busy = false; _status = ''; });
    }
  }

  Widget _card({required String title, required String desc, required VoidCallback onTap, Widget? child}) {
    return Card(
      color: Colors.white,
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
            const SizedBox(height: 12),
            child ?? Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(onPressed: _busy ? null : onTap, child: const Text('选择文件执行')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('实验功能')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                title: '提取动态库 Key',
                desc: '上传包含 libygsiyu.so 的 lib.zip，提取每个动态库的 post_key / xor_key（对应 /extract_libs）',
                onTap: _extractLibs,
                child: _keys.isEmpty
                    ? null
                    : Column(
                        children: _keys.map((k) => Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8FA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD0D7DE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(k.path, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF58A6FF))),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () { Clipboard.setData(ClipboardData(text: k.postKey)); _toast('post_key 已复制'); },
                                child: Text('post_key: ${k.postKey}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                              ),
                              InkWell(
                                onTap: () { Clipboard.setData(ClipboardData(text: k.xorKey)); _toast('xor_key 已复制'); },
                                child: Text('xor_key:  ${k.xorKey}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
              ),
              _card(
                title: '动态加密修复',
                desc: '上传 dex 包(zip/apk)与待修复源码 zip，将加密调用替换为明文映射，返回修复后源码包（对应 /repair_dynamic）',
                onTap: _runRepair,
                child: _repair == null
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text('dex: ${_repair!.dexCount}  映射: ${_repair!.mappingCount}  改动文件: ${_repair!.modifiedFileCount}  替换: ${_repair!.replacedCount}',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF2E7D32))),
                          if (_repair!.modifiedFiles.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_repair!.modifiedFiles.join('\n'),
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF757575))),
                            ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _busy ? null : _downloadRepair,
                            icon: const Icon(Icons.download, size: 18),
                            label: Text('下载 ${_repair!.zipName}'),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          if (_busy) ...[
            const ModalBarrier(dismissible: false, color: Colors.black45),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_status.isNotEmpty)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                color: const Color(0xFFE6E6E6),
                padding: const EdgeInsets.all(10),
                child: Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black87)),
              ),
            ),
        ],
      ),
    );
  }
}