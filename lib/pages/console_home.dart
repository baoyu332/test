
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'source_viewer_page.dart';
import 'tools_page.dart';

enum _C { grey, black, red, blue }

class _Line {
  final String t;
  final _C c;
  _Line(this.t, this.c);
}

Widget _greyBtn(BuildContext ctx, String t, VoidCallback? on) => ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE6E6E6),
        foregroundColor: Colors.black87,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
      ),
      onPressed: on,
      child: Text(t, style: const TextStyle(fontSize: 16)),
    );

class ConsoleHome extends StatefulWidget {
  const ConsoleHome({super.key});

  @override
  State<ConsoleHome> createState() => _ConsoleHomeState();
}

class _ConsoleHomeState extends State<ConsoleHome> {
  final _api = ApiService();
  final _scroll = ScrollController();
  final _lines = <_Line>[];

  Uint8List? _apkBytes;
  String _apkName = '';
  String _apkPath = '';
  ApkInfo? _info;
  DecryptResult? _result;
  final _found = <String>[];
  final _patch = <String, String>{};
  bool _so = false;
  bool _busy = false;
  bool _dialogOpen = false;

  bool get _lock => _busy;

  @override
  void initState() {
    super.initState();
    _welcome();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPathDialog());
  }

  void _welcome() {
    _lines.addAll([
      _Line('Welcome to iAppDecoder', _C.grey),
      _Line('Copyright © 2026 Mt论坛-暴雨', _C.grey),
      _Line('All Rights Reserved', _C.grey),
      _Line('暴雨:  QQ=1432319407', _C.grey),
      
      _Line('', _C.grey),
      _Line('Authority set:', _C.grey),

      _Line('反编译工具由Mt论坛-暴雨制作', _C.grey),
      _Line('Made by Mt论坛-暴雨', _C.grey),
      _Line('File name config:', _C.grey),
      _Line('Prefix: pre-', _C.grey),
      _Line('Suffix: -suf', _C.grey),
      _Line('', _C.grey),
      _Line('Idling', _C.red),
      _Line('', _C.grey),
    ]);
  }

  Color _col(_C c) {
    switch (c) {
      case _C.grey:
        return const Color(0xFF9E9E9E);
      case _C.black:
        return const Color(0xFF212121);
      case _C.red:
        return const Color(0xFFC62828);
      case _C.blue:
        return const Color(0xFF1565C0);
    }
  }

  void _add(String t, _C c) {
    if (!mounted) return;
    setState(() => _lines.add(_Line(t, c)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _say(String t, _C c, [int ms = 100]) async {
    _add(t, c);
    await Future.delayed(Duration(milliseconds: ms));
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _startDecode() async {
    if (_apkBytes == null) {
      _toast('请先选择 APK 文件');
      return;
    }
    if (_busy) return;
    if (_dialogOpen) {
      Navigator.of(context).pop();
      _dialogOpen = false;
    }
    setState(() {
      _busy = true;
      _result = null;
      _found.clear();
    });
    try {
      await _say('Start to decode', _C.red);
      await _say('Getting necessary files', _C.black);
      final info = await _api.extractApk(
        _apkBytes!,
        _apkName,
        onProgress: (p) => _add('Uploading chunk ${p.chunkIndex}/${p.chunkCount}', _C.black),
      );
      _info = info;
      await _say('Parsed AXML', _C.black);
      await _say('Preparation finished', _C.black);
      await _say('', _C.grey);
      if (info.libSoBytes == null) {
        await _say('lib.so not found in APK', _C.red);
        return;
      }
      await _say('Start decryption', _C.red);
      await _say('', _C.grey);

      String pick(String k, String fb) {
        final v = _patch[k];
        return (v != null && v.isNotEmpty) ? v : fb;
      }

      final params = <String, String>{
        'package_name': pick('package_name', info.packageName),
        'version_name': pick('version_name', info.versionName),
        'version_code': pick('version_code', info.versionCode),
        'app_name': pick('app_name', info.appName),
        'dek': pick('dek', info.dek ?? ''),
        'mode': pick('mode', info.detectedMode),
        'entry_file': pick('entry_file', 'mian.iyu'),
      };
      for (final k in ['sok', 'sign_key', 'sign_b64', 'pwd_key', 'post_key', 'xor_key']) {
        final v = pick(k, k == 'sok' ? (info.sok ?? '') : '');
        if (v.isNotEmpty) params[k] = v;
      }
      if ((params['dek'] ?? '').isEmpty) {
        await _say('Missing dek, use [P] Patch Config', _C.red);
        return;
      }

      Uint8List? native;
      if (_so && info.nativeSoBytes != null) {
        native = info.nativeSoBytes;
        await _say('[SO] attach ${info.nativeSoName}', _C.red);
      }
      final r = await _api.decrypt(
        libSoBytes: info.libSoBytes!,
        libSoName: info.libSoName,
        nativeSoBytes: native,
        nativeSoName: info.nativeSoName,
        params: params,
      );
      _result = r;
      final outPath = await _writeOut(params['package_name']!, r.files);
      for (final name in r.files.keys) {
        await _say('Processing file [$name]', _C.black);
        await _say('Preview [$name]', _C.black);
        final preview = r.files[name]!.split('\n').first;
        await _say(preview.length > 48 ? preview.substring(0, 48) : preview, _C.blue);
        await _say('Writing $name to disk', _C.blue);
        await _say('', _C.grey);
        setState(() => _found.add(name));
      }
      for (final f in r.failed) {
        await _say('Failed [${f.name}] ${f.error}', _C.red);
      }
      await _say(r.cacheHit ? 'Decryption finished (cache hit)' : 'Decryption finished', _C.black);
      _showDone(outPath, r);
    } on ApiException catch (e) {
      await _say('$e', _C.red);
      await _say('Use [P] Patch Config and retry', _C.red);
    } catch (e) {
      await _say('Error: $e', _C.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _writeOut(String pkg, Map<String, String> files) async {
    Future<String> writeAll(Directory dir) async {
      await dir.create(recursive: true);
      for (final e in files.entries) {
        final f = File('${dir.path}${Platform.pathSeparator}${e.key.replaceAll('/', '_')}');
        await f.writeAsString(e.value, flush: true);
      }
      return dir.path;
    }

    try {
      return await writeAll(Directory('/storage/emulated/0/Download/iAppDecode/$pkg'));
    } catch (_) {
      final ext = await getExternalStorageDirectory();
      final base = ext?.path ?? (await getApplicationDocumentsDirectory()).path;
      return writeAll(
        Directory('$base${Platform.pathSeparator}iAppDecode${Platform.pathSeparator}$pkg'),
      );
    }
  }

  void _showPathDialog() {
    _dialogOpen = true;
    final ctrl = TextEditingController(text: _apkPath);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('路径:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      readOnly: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _greyBtn(dctx, '选择文件', () async {
                    final res = await FilePicker.pickFile(
                      type: FileType.custom,
                      allowedExtensions: ['apk'],
                    );
                    if (res == null) return;
                    _apkBytes = await res.readAsBytes();
                    _apkName = res.name;
                    _apkPath = res.path ?? _apkName;
                    setD(() => ctrl.text = _apkPath);
                  }),
                  _greyBtn(dctx, '开始解密', () => _startDecode()),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  _link('如何保护你的iApp>', () => _toast('请勿泄露你的密钥与算法逻辑')),
                  _link('加群交流>', () => _toast('MT论坛 iAppDecoder 帖内加群')),
                  _link('联系开发者>', () => _toast('Mt论坛-暴雨: QQ=1432319407')),
                  _link('实验功能>', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsPage()))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _link(String t, VoidCallback on) => TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 2),
          minimumSize: const Size(40, 30),
        ),
        onPressed: on,
        child: Text(t, style: const TextStyle(color: Color(0xFF1565C0), fontSize: 14)),
      );

  void _menuR() {
    if (_lock) return;
    setState(() {
      _lines.clear();
      _apkBytes = null;
      _apkName = '';
      _apkPath = '';
      _info = null;
      _result = null;
      _found.clear();
      _patch.clear();
      _so = false;
    });
    _welcome();
    _showPathDialog();
  }

  Future<void> _menuP() async {
    if (_lock) return;
    final base = <String, String>{
      'app_name': _patch['app_name'] ?? _info?.appName ?? '',
      'version_code': _patch['version_code'] ?? _info?.versionCode ?? '',
      'version_name': _patch['version_name'] ?? _info?.versionName ?? '',
      'package_name': _patch['package_name'] ?? _info?.packageName ?? '',
    };
    final r = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => PatchConfigDialog(initial: base),
    );
    if (r == null) return;
    setState(() {
      _patch
        ..clear()
        ..addAll(r);
    });
    _add('Patch applied: ${r.length} fields', _C.red);
    if (_apkBytes != null) _startDecode();
  }

  Future<void> _menuS() async {
    if (_lock) return;
    final r = _result;
    if (r == null || r.files.isEmpty) {
      _toast('当前没有已解密的文件');
      return;
    }
    final name = await showDialog<String>(context: context, builder: (_) => const SearchFileDialog());
    if (name == null || name.trim().isEmpty) return;
    final q = name.trim().toLowerCase();
    final hit = r.files.keys.where((k) => k.toLowerCase().contains(q)).toList();
    if (hit.isEmpty) {
      _add('File [$name] not found', _C.red);
      _toast('未找到文件: $name');
      return;
    }
    _openViewer(hit.first);
  }

  Future<void> _menuW() async {
    if (_lock) return;
    final r = _result;
    if (r == null || r.files.isEmpty) {
      _toast('当前没有已解密的文件');
      return;
    }
    String? sel;
    if (r.files.length == 1) {
      sel = r.files.keys.first;
    } else {
      sel = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Center(child: Text('选择文件重写', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: SizedBox(
              width: 280,
              child: ListView(
                shrinkWrap: true,
                children: r.files.keys
                    .map((k) => ListTile(
                          dense: true,
                          title: Text(k, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
                          onTap: () => Navigator.pop(context, k),
                        ))
                    .toList(),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))],
        ),
      );
    }
    if (sel == null) return;
    final s = sel;
    final edited = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => SourceViewerPage(fileName: s, content: r.files[s]!, editable: true)),
    );
    if (edited == null || edited == r.files[s]) return;
    setState(() => _result!.files[s] = edited);
    _add('Writing $s to disk', _C.blue);
    _toast('已重写并保存: $s');
  }

  void _openViewer(String name) {
    final c = _result?.files[name];
    if (c == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SourceViewerPage(fileName: name, content: c)),
    );
  }

  void _showDone(String outPath, DecryptResult r) {
    final files = r.files.keys.toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DonePage(outPath: outPath, files: files),
      ),
    );
    _toast('解密已完成 输出目录: $outPath');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text('iAppDecoder', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black26, width: 1.5))),
              child: Row(
                children: [
                  _letter('R', _menuR),
                  _v(),
                  _letter('P', _menuP),
                  _v(),
                  _letter('S', _menuS),
                  _v(),
                  _letter('W', _menuW),
                  _v(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('SO:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                  Checkbox(
                    value: _so,
                    onChanged: _lock
                        ? null
                        : (v) {
                            setState(() => _so = v ?? false);
                            _add('SO mode ${_so ? 'enabled' : 'disabled'}', _C.red);
                          },
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black26, width: 1.5))),
              child: Text(
                '已发现: ${_found.join(' , ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: _lines.length,
                itemBuilder: (_, i) {
                  final l = _lines[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      'Decoder-> ${l.t}',
                      style: TextStyle(fontSize: 15, height: 1.35, color: _col(l.c)),
                    ),
                  );
                },
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  Widget _letter(String s, VoidCallback on) => Expanded(
        child: InkWell(
          onTap: _lock ? null : on,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            child: Text(
              s,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _lock ? Colors.grey : Colors.black),
            ),
          ),
        ),
      );

  Widget _v() => Container(width: 1, height: 30, color: Colors.black26);
}

class _DonePage extends StatelessWidget {
  final String outPath;
  final List<String> files;
  const _DonePage({required this.outPath, required this.files});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('解密已完成', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  const Text('输出目录:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SelectableText(outPath, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  Text('已发现: ${files.length} 个文件', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  for (var i = 0; i < files.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '  ${i + 1}. ${files[i]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('如需解密其他iApp,请重启程序', style: TextStyle(fontSize: 14, color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PatchConfigDialog extends StatefulWidget {
  final Map<String, String> initial;
  const PatchConfigDialog({super.key, required this.initial});

  @override
  State<PatchConfigDialog> createState() => _PatchConfigDialogState();
}

class _PatchConfigDialogState extends State<PatchConfigDialog> {
  late final _app = TextEditingController(text: widget.initial['app_name'] ?? '');
  late final _vcode = TextEditingController(text: widget.initial['version_code'] ?? '');
  late final _vname = TextEditingController(text: widget.initial['version_name'] ?? '');
  late final _pkg = TextEditingController(text: widget.initial['package_name'] ?? '');

  @override
  void dispose() {
    _app.dispose();
    _vcode.dispose();
    _vname.dispose();
    _pkg.dispose();
    super.dispose();
  }

  Widget _row(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            Expanded(
              child: TextField(
                controller: c,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Center(child: Text('Patch Config', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black))),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: Text('程序无法识别? 试试自己填入吧!', style: TextStyle(fontSize: 13, color: Colors.grey))),
          const SizedBox(height: 10),
          _row('应用名:', _app),
          _row('版本号:', _vcode),
          _row('版本名:', _vname),
          _row('包名:', _pkg),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _greyBtn(context, '取消', () => Navigator.pop(context)),
              _greyBtn(context, '开始', () => Navigator.pop(context, {
                    'app_name': _app.text.trim(),
                    'version_code': _vcode.text.trim(),
                    'version_name': _vname.text.trim(),
                    'package_name': _pkg.text.trim(),
                  })),
            ],
          ),
        ],
      ),
    );
  }
}

class SearchFileDialog extends StatefulWidget {
  const SearchFileDialog({super.key});

  @override
  State<SearchFileDialog> createState() => _SearchFileDialogState();
}

class _SearchFileDialogState extends State<SearchFileDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Center(child: Text('Search File', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(
            child: Text(
              '没有找到想要的文件?\n试试手动输入文件名进行查找吧!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('文件名:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _c,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true, hintText: 'FileName', border: UnderlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _greyBtn(context, '取消', () => Navigator.pop(context)),
              _greyBtn(context, '搜索', () => Navigator.pop(context, _c.text)),
            ],
          ),
        ],
      ),
    );
  }
}