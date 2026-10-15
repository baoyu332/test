
import 'package:flutter/material.dart';

class PatchPage extends StatefulWidget {
  final Map<String, String> initial;
  const PatchPage({super.key, required this.initial});

  @override
  State<PatchPage> createState() => _PatchPageState();
}

class _PatchPageState extends State<PatchPage> {
  late final Map<String, TextEditingController> _ctrl = {
    for (final e in widget.initial.entries) e.key: TextEditingController(text: e.value),
  };
  late String _mode = widget.initial['mode'] ?? 'auto';

  static const _requiredKeys = ['package_name', 'version_name', 'version_code', 'app_name', 'dek'];

  @override
  void dispose() {
    for (final c in _ctrl.values) c.dispose();
    super.dispose();
  }

  Widget _field(String key, String label, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrl.putIfAbsent(key, () => TextEditingController()),
        obscureText: obscure,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(
          labelText: label + (_requiredKeys.contains(key) ? ' *' : ''),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('P: 手动填写参数（Patch）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('必填参数', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF58A6FF))),
          const SizedBox(height: 12),
          _field('package_name', '包名 package_name'),
          _field('version_name', '版本名 version_name'),
          _field('version_code', '版本号 version_code'),
          _field('app_name', '应用名 app_name'),
          _field('dek', 'dex 密钥 dek', obscure: true),
          const SizedBox(height: 16),
          const Text('可选参数', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B949E))),
          const SizedBox(height: 12),
          _field('sok', 'so 密钥 sok', obscure: true),
          _field('sign_key', '签名 md5 sign_key'),
          _field('sign_b64', '签名 base64 sign_b64'),
          _field('pwd_key', '用户加密密码 pwd_key', obscure: true),
          _field('post_key', '手动 post_key (hex)'),
          _field('xor_key', '手动 xor_key (hex)'),
          _field('entry_file', '入口文件 (默认 mian.iyu)'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: '解密模式 mode', border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('auto - 自动尝试')),
              DropdownMenuItem(value: 'current', child: Text('current - 当前算法')),
              DropdownMenuItem(value: 'legacy', child: Text('legacy - 旧版算法')),
              DropdownMenuItem(value: 'legacy4', child: Text('legacy4 - 旧版4位sok')),
            ],
            onChanged: (v) => setState(() => _mode = v ?? 'auto'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              final out = <String, String>{'mode': _mode};
              _ctrl.forEach((k, c) {
                if (k != 'mode' && c.text.trim().isNotEmpty) out[k] = c.text.trim();
              });
              Navigator.pop(context, out);
            },
            child: const Text('应用并重新解析'),
          ),
        ],
      ),
    );
  }
}