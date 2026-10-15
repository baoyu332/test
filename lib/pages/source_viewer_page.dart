
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class SourceViewerPage extends StatefulWidget {
  final String fileName;
  final String content;
  final bool editable;
  const SourceViewerPage({
    super.key,
    required this.fileName,
    required this.content,
    this.editable = false,
  });

  @override
  State<SourceViewerPage> createState() => _SourceViewerPageState();
}

class _SourceViewerPageState extends State<SourceViewerPage> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.content);
  late bool _editing = widget.editable;
  bool _wrap = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final bytes = utf8.encode(_ctrl.text);
    final x = XFile.fromData(bytes, mimeType: 'text/plain', name: widget.fileName);
    await SharePlus.instance.share(ShareParams(files: [x], text: widget.fileName));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
        actions: [
          IconButton(
            tooltip: '切换编辑（W: 重写）',
            icon: Icon(_editing ? Icons.visibility : Icons.edit),
            onPressed: () => setState(() => _editing = !_editing),
          ),
          IconButton(
            tooltip: '自动换行',
            icon: Icon(_wrap ? Icons.wrap_text : Icons.format_align_left),
            onPressed: () => setState(() => _wrap = !_wrap),
          ),
          IconButton(
            tooltip: '复制全文',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _ctrl.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
            },
          ),
          IconButton(tooltip: '导出分享', icon: const Icon(Icons.share), onPressed: _share),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFFEEEEEE),
            child: Text(
              '${_ctrl.text.length} 字符 · ${_ctrl.text.split('\n').length} 行' + (_editing ? ' · 编辑模式' : ''),
              style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: _editing
                ? TextField(
                    controller: _ctrl,
                    onChanged: (_) => setState(() {}),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF212121)),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(12),
                      border: InputBorder.none,
                      fillColor: Colors.white,
                      filled: true,
                    ),
                  )
                : SingleChildScrollView(
                    child: _wrap
                        ? SelectableText(
                            _ctrl.text,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF212121), height: 1.5),
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: SelectableText(
                              _ctrl.text,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF212121), height: 1.5),
                            ),
                          ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _editing
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _ctrl.text = widget.content;
                          setState(() {});
                        },
                        child: const Text('还原'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _ctrl.text),
                        child: const Text('应用修改'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}