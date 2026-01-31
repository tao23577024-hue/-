import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ================= 配置区 =================
const String apiKey = '在此处粘贴你的API_KEY';
// ========================================

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gray Fund Stable',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        primaryColor: Colors.blueGrey,
        cardColor: const Color(0xFF2D2D2D),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E), 
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const PortfolioPage(),
    const AiAssistantPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: const Color(0xFF64B5F6),
        unselectedItemColor: Colors.grey.shade700,
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), label: '持仓'),
          BottomNavigationBarItem(icon: Icon(Icons.smart_toy_outlined), label: 'AI 助手'),
        ],
      ),
    );
  }
}

// ================= 1. 持仓页面 (更换新代理) =================

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});
  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  Map<String, double> myFunds = {};
  List<Map<String, dynamic>> displayData = [];
  bool _isLoading = true;
  bool _dataLoaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchOnlineData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('my_portfolio_v2');
      
      if (jsonStr != null && jsonStr.isNotEmpty) {
        Map<String, dynamic> decoded = json.decode(jsonStr);
        setState(() {
          myFunds = decoded.map((key, value) => MapEntry(key, (value as num).toDouble()));
        });
      }
    } catch (e) {
      print("Load Error: $e");
    } finally {
      setState(() {
        _dataLoaded = true;
      });
      _fetchOnlineData();
    }
  }

  Future<void> _saveLocalData() async {
    if (!_dataLoaded) return; 

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('my_portfolio_v2', json.encode(myFunds));
    } catch (e) {
      print("Save Error: $e");
    }
    _fetchOnlineData();
  }

  // === 核心修复区：使用 AllOrigins 代理 ===
  Future<void> _fetchOnlineData() async {
    if (myFunds.isEmpty) {
      if (mounted) setState(() { displayData = []; _isLoading = false; });
      return;
    }
    List<Map<String, dynamic>> tempResults = [];
    
    final requests = myFunds.keys.map((code) async {
      try {
        // 目标网址
        final targetUrl = "https://fundgz.1234567.com.cn/js/$code.js?rt=${DateTime.now().millisecondsSinceEpoch}";
        // 使用新代理并编码
        final proxyUrl = Uri.parse("https://api.allorigins.win/raw?url=${Uri.encodeComponent(targetUrl)}");
        
        final response = await http.get(proxyUrl).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          String body = utf8.decode(response.bodyBytes);
          if (body.contains('jsonpgz')) {
            final jsonStr = body.substring(8, body.length - 2);
            final data = json.decode(jsonStr);
            return data;
          }
        }
      } catch (e) {
        // 忽略错误
      }
      return null;
    });

    final results = await Future.wait(requests);

    for (var data in results) {
      if (data != null) {
        String code = data['fundcode'];
        if (myFunds.containsKey(code)) {
          double amount = myFunds[code]!;
          double rate = double.tryParse(data['gszzl'] ?? '0') ?? 0.0;
          double profit = amount * (rate / 100);
          
          tempResults.add({
            'code': code,
            'name': data['name'],
            'rate': rate,
            'val': data['gsz'],
            'amount': amount,
            'profit': profit,
            'time': data['gztime']
          });
        }
      }
    }
    
    if (mounted) {
      setState(() {
        displayData = tempResults;
        _isLoading = false;
      });
    }
  }

  void _addNewFund(String code) {
    if (!_dataLoaded) return;

    if (!myFunds.containsKey(code)) {
      setState(() => myFunds[code] = 0.0);
      _saveLocalData();
      Navigator.push(context, MaterialPageRoute(builder: (c) => FundDetailPage(
        code: code, name: "新添加基金", initialAmount: 0.0, 
        onSave: (val) { setState(() => myFunds[code] = val); _saveLocalData(); },
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalDayProfit = displayData.fold(0.0, (sum, item) => sum + item['profit']);
    double totalAssets = displayData.fold(0.0, (sum, item) => sum + item['amount']);

    return Column(
      children: [
        Container(
          width: double.infinity, margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2D2D2D), Color(0xFF222222)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("总资产 (CNY)", style: TextStyle(color: Colors.grey, fontSize: 13, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text("¥${totalAssets.toStringAsFixed(2)}", style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Roboto')),
            const SizedBox(height: 16),
            Row(children: [
              const Text("今日估值盈亏: ", style: TextStyle(color: Colors.grey, fontSize: 13)),
              Text("${totalDayProfit>=0?'+':''}${totalDayProfit.toStringAsFixed(2)}", 
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: totalDayProfit>=0 ? const Color(0xFFFF5252) : const Color(0xFF4CAF50))),
            ]),
          ]),
        ),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(
              children: [
                const Text("持仓列表", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (_isLoading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)),
              ],
            ),
            IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF64B5F6), size: 30), onPressed: () => showSearch(context: context, delegate: FundSearchDelegate(_addNewFund))),
          ]),
        ),

        Expanded(
          child: !_dataLoaded 
          ? const Center(child: Text("正在恢复数据...", style: TextStyle(color: Colors.grey)))
          : displayData.isEmpty
            ? const Center(child: Text("暂无持仓，点击右上角 + 添加", style: TextStyle(color: Colors.grey)))
            : ListView.builder(
              itemCount: displayData.length,
              itemBuilder: (context, index) {
                final item = displayData[index];
                bool isUp = item['rate'] >= 0;
                Color txtColor = isUp ? const Color(0xFFFF5252) : const Color(0xFF4CAF50);
                
                return GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => FundDetailPage(
                      code: item['code'], name: item['name'], initialAmount: item['amount'],
                      onSave: (val) { setState(() => myFunds[item['code']] = val); _saveLocalData(); },
                      onDelete: () { setState(() { myFunds.remove(item['code']); displayData.removeAt(index); }); _saveLocalData(); Navigator.pop(context); }
                    )));
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF2D2D2D), borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item['name'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)), child: Text(item['code'], style: const TextStyle(fontSize: 10, color: Colors.white54))),
                          const SizedBox(width: 8),
                          Icon(Icons.access_time, size: 10, color: Colors.grey),
                          const SizedBox(width: 2),
                          Text(item['time'].toString().substring(5), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ]),
                      ])),
                      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text("估值", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        Text(item['val'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                      ])),
                      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text("${isUp?'+':''}${item['rate']}%", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: txtColor)),
                          const SizedBox(height: 2),
                          Text("${item['profit']>=0?'+':''}${item['profit'].toStringAsFixed(1)}", style: TextStyle(fontSize: 12, color: txtColor.withOpacity(0.8))),
                      ])),
                    ]),
                  ),
                );
              },
            ),
        ),
      ],
    );
  }
}

// ================= 2. 详情页 (更换新代理) =================

class FundDetailPage extends StatefulWidget {
  final String code;
  final String name;
  final double initialAmount;
  final Function(double) onSave;
  final VoidCallback? onDelete;

  const FundDetailPage({super.key, required this.code, required this.name, required this.initialAmount, required this.onSave, this.onDelete});

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage> {
  late TextEditingController _amountCtrl;
  List<FlSpot> _chartData = [];
  bool _loadingChart = true;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.initialAmount.toString());
    _fetchHistoryData();
  }

  // === 修复点：历史净值请求 ===
  Future<void> _fetchHistoryData() async {
    try {
      final targetUrl = "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNHisNetList?product=EFund&appType=ttjj&FCODE=${widget.code}&PAGEINDEX=1&PAGESIZE=20";
      final proxyUrl = Uri.parse("https://api.allorigins.win/raw?url=${Uri.encodeComponent(targetUrl)}");
      
      final response = await http.get(proxyUrl);
      if (response.statusCode == 200) {
        String body = utf8.decode(response.bodyBytes);
        final data = json.decode(body);
        final List list = data['Datas'];
        List<FlSpot> temp = [];
        for (int i = list.length - 1; i >= 0; i--) {
          double val = double.tryParse(list[i]['DWJZ']) ?? 0.0;
          temp.add(FlSpot((list.length - 1 - i).toDouble(), val));
        }
        if (mounted) setState(() { _chartData = temp; _loadingChart = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingChart = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name), actions: [
        if (widget.onDelete != null)
          IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), onPressed: widget.onDelete)
      ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("近20个交易日净值", style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 20),
            Container(
              height: 220, padding: const EdgeInsets.only(right: 16),
              child: _loadingChart 
                ? const Center(child: CupertinoActivityIndicator())
                : _chartData.isEmpty ? const Center(child: Text("暂无数据")) : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _chartData, isCurved: true, color: const Color(0xFF64B5F6), barWidth: 3, isStrokeCapRound: true, dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: const Color(0xFF64B5F6).withOpacity(0.1)),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 40),
            const Text("持有金额设置", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF2D2D2D), borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _amountCtrl, 
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 18, color: Colors.white),
                decoration: const InputDecoration(
                  prefixText: "¥ ", prefixStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64B5F6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  double? val = double.tryParse(_amountCtrl.text);
                  if (val != null) { widget.onSave(val); Navigator.pop(context); }
                },
                child: const Text("保存持有金额", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ================= 3. AI 助手 (带 Webview) =================

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});
  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  int _mode = 0; 
  late final WebViewController _webController;
  final TextEditingController _textCtrl = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  GenerativeModel? _model;
  ChatSession? _chat;

  @override
  void initState() {
    super.initState();
    if (apiKey.length > 10) {
      _model = GenerativeModel(model: 'gemini-pro', apiKey: apiKey);
      _chat = _model!.startChat();
    }
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E1E1E))
      ..setUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1")
      ..loadRequest(Uri.parse('https://gemini.google.com/'));
  }

  void _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() { _messages.add({'role': 'user', 'msg': text}); _isLoading = true; _textCtrl.clear(); });
    try {
      final response = await _chat!.sendMessage(Content.text(text));
      setState(() { _messages.add({'role': 'ai', 'msg': response.text ?? ''}); _isLoading = false; });
    } catch (e) {
      setState(() { _messages.add({'role': 'ai', 'msg': '网络错误，请检查 Key'}); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          child: Row(
            children: [
              const Text("AI 投资顾问", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              CupertinoSlidingSegmentedControl<int>(
                backgroundColor: const Color(0xFF2D2D2D),
                thumbColor: const Color(0xFF64B5F6),
                groupValue: _mode,
                children: {
                  0: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text("极速模式", style: TextStyle(color: _mode == 0 ? Colors.black : Colors.white, fontSize: 13))),
                  1: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text("官网模式", style: TextStyle(color: _mode == 1 ? Colors.black : Colors.white, fontSize: 13))),
                },
                onValueChanged: (val) => setState(() => _mode = val!),
              ),
            ],
          ),
        ),
        Expanded(
          child: _mode == 0 ? _buildChatUI() : WebViewWidget(controller: _webController),
        ),
      ],
    );
  }

  Widget _buildChatUI() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty 
          ? const Center(child: Text("分析市场、预测走势，请直接提问。", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                bool isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 300),
                    decoration: BoxDecoration(color: isUser ? const Color(0xFF64B5F6) : const Color(0xFF333333), borderRadius: BorderRadius.circular(12)),
                    child: Text(msg['msg']!, style: TextStyle(color: isUser ? Colors.black : Colors.white)),
                  ),
                );
              },
            ),
        ),
        if (_isLoading) const SizedBox(height: 20, child: CupertinoActivityIndicator()),
        Container(
          padding: const EdgeInsets.all(12), color: const Color(0xFF1E1E1E),
          child: Row(children: [
            Expanded(child: TextField(controller: _textCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "输入问题...", filled: true, fillColor: const Color(0xFF2D2D2D), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)), onSubmitted: (_)=>_sendMessage())),
            IconButton(icon: const Icon(Icons.send, color: Color(0xFF64B5F6)), onPressed: _sendMessage),
          ]),
        ),
      ],
    );
  }
}

class FundSearchDelegate extends SearchDelegate {
  final Function(String) onSelect;
  FundSearchDelegate(this.onSelect);
  @override ThemeData appBarTheme(BuildContext context) => ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF1E1E1E), appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1E1E1E)));
  @override List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  @override Widget buildResults(BuildContext context) => _search();
  @override Widget buildSuggestions(BuildContext context) => _search();
  Widget _search() {
    if (query.length < 2) return const SizedBox();
    return FutureBuilder(
      // === 修复点：基金搜索也换新代理 ===
      future: http.get(Uri.parse("https://api.allorigins.win/raw?url=${Uri.encodeComponent('https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx?m=1&key=$query')}")),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CupertinoActivityIndicator());
        try {
          final String body = utf8.decode(snapshot.data!.bodyBytes);
          final List datas = json.decode(body)['Datas'];
          return ListView.builder(itemCount: datas.length, itemBuilder: (context, index) {
            final item = datas[index];
            return ListTile(title: Text(item['NAME'], style: const TextStyle(color: Colors.white)), subtitle: Text(item['CODE'], style: const TextStyle(color: Colors.grey)), onTap: () { onSelect(item['CODE']); close(context, null); });
          });
        } catch (e) { return const SizedBox(); }
      },
    );
  }
}
