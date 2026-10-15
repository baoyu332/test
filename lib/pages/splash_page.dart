
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'console_home.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _apiUrl = 'https://gitee.com/api/v5/repos/iapk/iapk/contents/status.txt';
  static const _rawUrl = 'https://gitee.com/iapk/iapk/raw/master/status.txt';
  bool _checking = true;
  bool _blocked = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _checkRemote();
  }

  Future<String?> _fetch(String url) async {
    final resp = await http.get(
      Uri.parse(url),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      },
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  Future<void> _checkRemote() async {
    String detail = '';
    try {
      String text;
      try {
        final body = await _fetch(_apiUrl);
        final json = jsonDecode(body!) as Map<String, dynamic>;
        final b64 = (json['content'] as String? ?? '').replaceAll('\n', '').replaceAll('\r', '');
        text = utf8.decode(base64Decode(b64), allowMalformed: true);
      } catch (e) {
        detail = 'api通道: $e; ';
        text = await _fetch(_rawUrl) ?? '';
      }
      setState(() {
        _checking = false;
        if (text.contains('暴雨')) {
          _blocked = false;
          _msg = '';
        } else {
          _blocked = true;
          _msg = '该工具已暂停使用，请联系开发者';
        }
      });
    } catch (e) {
      setState(() {
        _checking = false;
        _blocked = true;
        _msg = '网络异常: $detail$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
            const Spacer(flex: 3),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF4FC1E9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: Container(width: 32, height: 32, color: Colors.white),
                  ),
                  Positioned(
                    left: 22,
                    top: 22,
                    child: Container(
                      width: 52,
                      height: 52,
                      color: Colors.white,
                      child: const Icon(Icons.sync, color: Colors.black87, size: 30),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'iAppDecoder',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: Colors.black),
            ),
            const SizedBox(height: 30),
            if (_checking)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (!_checking && _blocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 15),
                ),
              ),
            SizedBox(
              width: 220,
              child: TextField(
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '默认用户',
                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 18),
                  border: InputBorder.none,
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE6E6E6),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                elevation: 2,
              ),
              onPressed: (_checking || _blocked)
                  ? null
                  : () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const ConsoleHome()),
                      ),
              child: const Text('进入软件', style: TextStyle(fontSize: 17)),
            ),
            const Spacer(flex: 2),
            const Text(
              '本程序为免费提供\n请勿尝试二改或破解',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFD32F2F), fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 8),
            const Text(
              'Powered by',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const Text('Mt论坛—暴雨', style: TextStyle(fontSize: 12, color: Colors.black87)),
            const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
