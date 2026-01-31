import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// ==========================================
//  AIzaSyC-XpOZ6hvyviJa65_Si0Ka3gji9hhSUt8
// ==========================================
const String apiKey = '在此处粘贴你的API_KEY'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glass Fund',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: '.SF Pro Text', // 尝试调用 iOS 系统字体
        scaffoldBackgroundColor: Colors.black, // 深色底兼容
      ),
      home: const GlassHome(),
    );
  }
}

// 玻璃特效组件
class GlassBox extends StatelessWidget {
  final Widget child;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassBox({super.key, required this.child, this.opacity = 0.15, this.padding, this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), // 强磨砂
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(opacity),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassHome extends StatefulWidget {
  const GlassHome({super.key});
  @override
  State<GlassHome> createState() => _GlassHomeState();
}

class _GlassHomeState extends State<GlassHome> {
  int _index = 0;
  final List<Widget> _pages = [const FundPage(), const ChatPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // 让内容延伸到任何地方
      body: Stack(
        children: [
          // 1. 动态极光背景
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2), Color(0xFF000000)], // 深邃紫黑风
              ),
            ),
          ),
          // 装饰光球
          Positioned(top: -100, right: -100, child: Container(width: 300, height: 300, decoration: BoxDecoration(color: const Color(0xFF00C6FF).withOpacity(0.4), shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 100, color: const Color(0xFF00C6FF))]))),
          Positioned(bottom: 100, left: -50, child: Container(width: 250, height: 250, decoration: BoxDecoration(color: const Color(0xFFFF0099).withOpacity(0.3), shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 100, color: const Color(0xFFFF0099))]))),

          // 2. 页面内容
          SafeArea(child: _pages[_index]),
        ],
      ),
      // 3. 悬浮玻璃导航
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(40, 0, 40, 40),
        height: 70,
        child: GlassBox(
          opacity: 0.1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _btn(0, CupertinoIcons.graph_square_fill, "行情"),
              const VerticalDivider(color: Colors.white24, width: 1, indent: 15, endIndent: 15),
              _btn(1, CupertinoIcons.chat_bubble_text_fill, "AI 助理"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(int i, IconData icon, String txt) {
    final bool sel = _index == i;
    return GestureDetector(
      onTap: () => setState(() => _index = i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: sel ? Colors.white : Colors.white38, size: 28),
          const SizedBox(height: 4),
          Text(txt, style: TextStyle(color: sel ? Colors.white : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// 基金页
class FundPage extends StatefulWidget {
  const FundPage({super.key});
  @override
  State<FundPage> createState() => _FundPageState();
}

class _FundPageState extends State<FundPage> {
  List<String> codes = ['009052', '012414'];
  List<Map> data = [];
  Timer? t;

  @override
  void initState() {
    super.initState();
    _load();
    t = Timer.periodic(const Duration(seconds: 10), (_) => _fetch());
  }
  @override void dispose() { t?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getStringList('c');
    if (s != null) codes = s;
    _fetch();
  }
  Future<void> _save() async { final p = await SharedPreferences.getInstance(); p.setStringList('c', codes); }

  Future<void> _fetch() async {
    List<Map> tmp = [];
    for (var c in codes) {
      try {
        final r = await http.get(Uri.parse("http://fundgz.1234567.com.cn/js/$c.js?rt=${DateTime.now().millisecondsSinceEpoch}"));
        if (r.statusCode == 200) {
          final s = r.body;
          tmp.add(json.decode(s.substring(8, s.length - 2)));
        }
      } catch (_) {}
    }
    if (mounted) setState(() => data = tmp);
  }

  void _add(String c) { if(!codes.contains(c)) { setState(() => codes.add(c)); _save(); _fetch(); } }
  void _del(String c) { setState(() { codes.remove(c); data.removeWhere((e)=>e['fundcode']==c); }); _save(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("我的持仓", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(CupertinoIcons.add_circled, color: Colors.white, size: 30), onPressed: () => showSearch(context: context, delegate: S(_add))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: data.length,
            itemBuilder: (ctx, i) {
              final d = data[i];
              final r = double.tryParse(d['gszzl']) ?? 0;
              final col = r >= 0 ? const Color(0xFFFF4D4D) : const Color(0xFF00E676); // 荧光红绿
              return Dismissible(
                key: Key(d['fundcode']),
                onDismissed: (_) => _del(d['fundcode']),
                child: GlassBox(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1),
                        const SizedBox(height: 5),
                        Text(d['fundcode'], style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(d['gsz'], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        Text("${r>=0?'+':''}${d['gszzl']}%", style: TextStyle(color: col, fontWeight: FontWeight.bold)),
                      ])
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// 搜索代理
class S extends SearchDelegate {
  final Function(String) cb; S(this.cb);
  @override List<Widget>? buildActions(BuildContext context) => [IconButton(icon:const Icon(Icons.clear),onPressed:()=>query='')];
  @override Widget? buildLeading(BuildContext context) => IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>close(context,null));
  @override Widget buildResults(BuildContext context) => _f();
  @override Widget buildSuggestions(BuildContext context) => _f();
  Widget _f() {
    if (query.length < 2) return const SizedBox();
    return FutureBuilder(
      future: http.get(Uri.parse("http://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx?m=1&key=$query")),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CupertinoActivityIndicator());
        try {
          final l = json.decode(s.data!.body)['Datas'] as List;
          return ListView.builder(itemCount: l.length, itemBuilder: (c, i) => ListTile(title: Text(l[i]['NAME']), subtitle: Text(l[i]['CODE']), onTap: (){ cb(l[i]['CODE']); close(c,null); }));
        } catch (_) { return const SizedBox(); }
      },
    );
  }
}

// 聊天页
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override State<ChatPage> createState() => _ChatPageState();
}
class _ChatPageState extends State<ChatPage> {
  final _c = TextEditingController();
  final List<Map> _m = [];
  bool _ld = false;
  GenerativeModel? _gm; ChatSession? _cs;

  @override void initState() {
    super.initState();
    if(apiKey.length > 10) { _gm = GenerativeModel(model: 'gemini-pro', apiKey: apiKey); _cs = _gm!.startChat(); }
  }

  void _s() async {
    final t = _c.text; if(t.isEmpty) return;
    setState(() { _m.add({'t':t,'u':true}); _ld=true; _c.clear(); });
    try {
      final r = await _cs!.sendMessage(Content.text(t));
      setState(() { _m.add({'t':r.text,'u':false}); _ld=false; });
    } catch (e) { setState(() { _m.add({'t':'Error','u':false}); _ld=false; }); }
  }

  @override
  Widget build(BuildContext context) {
    if(apiKey.length < 10) return const Center(child: Text("请填入 API Key", style: TextStyle(color: Colors.white)));
    return Column(
      children: [
        const Padding(padding: EdgeInsets.all(20), child: Align(alignment: Alignment.centerLeft, child: Text("AI 助手", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)))),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20,0,20,120),
          itemCount: _m.length,
          itemBuilder: (c,i) => Align(
            alignment: _m[i]['u'] ? Alignment.centerRight : Alignment.centerLeft,
            child: GlassBox(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(12),
              opacity: _m[i]['u'] ? 0.3 : 0.1,
              child: Text(_m[i]['t'], style: const TextStyle(color: Colors.white)),
            ),
          ),
        )),
        if(_ld) const CupertinoActivityIndicator(color: Colors.white),
        Container(
          margin: const EdgeInsets.fromLTRB(20,0,20,100),
          height: 50,
          child: GlassBox(
            child: Row(children: [
              Expanded(child: TextField(controller: _c, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(border: InputBorder.none, hintText: " 聊聊市场...", hintStyle: TextStyle(color: Colors.white38)), onSubmitted: (_)=>_s())),
              IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _s)
            ]),
          ),
        )
      ],
    );
  }
}
