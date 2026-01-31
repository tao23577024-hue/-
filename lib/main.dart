import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// ================= 配置区 =================
const String apiKey = 'AIzaSyC-XpOZ6hvyviJa65_Si0Ka3gji9hhSUt8';
// ========================================

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gray Fund',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF303030), // 中灰色背景
        primaryColor: Colors.blueGrey,
        cardColor: const Color(0xFF424242), // 卡片稍亮一点
        dialogBackgroundColor: const Color(0xFF424242),
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
    const ChatPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF212121), // 深灰底栏
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: '持仓'),
          BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'AI 分析'),
        ],
      ),
    );
  }
}

// ================= 1. 持仓页面 (核心功能) =================

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});
  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  // 数据结构：Code -> Amount (持有金额)
  Map<String, double> myFunds = {'009052': 1000.0, '012414': 500.0};
  List<Map<String, dynamic>> displayData = [];
  Timer? _timer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchOnlineData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // 加载本地存的“代码”和“金额”
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('my_portfolio');
    if (jsonStr != null) {
      Map<String, dynamic> decoded = json.decode(jsonStr);
      // 转换 dynamic 为 double
      setState(() {
        myFunds = decoded.map((key, value) => MapEntry(key, (value as num).toDouble()));
      });
    }
    _fetchOnlineData();
  }

  // 保存数据
  Future<void> _saveLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    String jsonStr = json.encode(myFunds);
    await prefs.setString('my_portfolio', jsonStr);
    _fetchOnlineData(); // 重新刷新界面
  }

  // 获取实时估值
  Future<void> _fetchOnlineData() async {
    if (myFunds.isEmpty) {
      if (mounted) setState(() => displayData = []);
      return;
    }

    List<Map<String, dynamic>> tempResults = [];
    double totalProfit = 0.0;

    for (var entry in myFunds.entries) {
      String code = entry.key;
      double amount = entry.value;

      try {
        final url = Uri.parse("http://fundgz.1234567.com.cn/js/$code.js?rt=${DateTime.now().millisecondsSinceEpoch}");
        final response = await http.get(url);
        
        if (response.statusCode == 200) {
          String body = response.body;
          if (body.length > 10) {
            final jsonStr = body.substring(8, body.length - 2);
            final data = json.decode(jsonStr);
            
            // 计算当日收益
            double rate = double.tryParse(data['gszzl']) ?? 0.0;
            double profit = amount * (rate / 100);
            
            tempResults.add({
              'code': data['fundcode'],
              'name': data['name'],
              'rate': rate, // 涨跌幅 %
              'val': data['gsz'], // 净值
              'amount': amount, // 持仓金额
              'profit': profit, // 当日盈亏金额
              'time': data['gztime']
            });
          }
        }
      } catch (e) {
        // 获取失败保留旧数据或显示错误
      }
    }

    if (mounted) {
      setState(() {
        displayData = tempResults;
      });
    }
  }

  // 修改仓位弹窗
  void _editPosition(String code, double currentAmount) {
    TextEditingController _ctrl = TextEditingController(text: currentAmount.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("调整持仓金额"),
        content: TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: "元"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              double? newAmount = double.tryParse(_ctrl.text);
              if (newAmount != null) {
                setState(() {
                  myFunds[code] = newAmount;
                });
                _saveLocalData();
                Navigator.pop(ctx);
              }
            },
            child: const Text("确认", style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // 添加基金逻辑
  void _addNewFund(String code) {
    if (!myFunds.containsKey(code)) {
      setState(() {
        myFunds[code] = 0.0; // 默认持有 0 元
      });
      _saveLocalData();
      // 自动弹出编辑框让用户输钱
      Future.delayed(const Duration(milliseconds: 500), () {
        _editPosition(code, 0.0);
      });
    }
  }

  // 删除基金
  void _deleteFund(String code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除?"),
        content: const Text("将从列表中移除该基金。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
             onPressed: () {
               setState(() {
                 myFunds.remove(code);
                 displayData.removeWhere((element) => element['code'] == code);
               });
               _saveLocalData();
               Navigator.pop(ctx);
             }, 
             child: const Text("删除", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 算总收益
    double totalDayProfit = displayData.fold(0.0, (sum, item) => sum + item['profit']);
    double totalAssets = displayData.fold(0.0, (sum, item) => sum + item['amount']);

    return Column(
      children: [
        // 顶部总览卡片
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF424242),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("总资产 (估)", style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Text(totalAssets.toStringAsFixed(2), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("当日预估收益:", style: TextStyle(color: Colors.white70)),
                  Text(
                    "${totalDayProfit >= 0 ? '+' : ''}${totalDayProfit.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold,
                      color: totalDayProfit >= 0 ? const Color(0xFFFF5252) : const Color(0xFF69F0AE),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),

        // 列表标题 + 添加按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("持仓列表", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.blueAccent, size: 28),
                onPressed: () => showSearch(context: context, delegate: FundSearchDelegate(_addNewFund)),
              )
            ],
          ),
        ),

        // 列表区
        Expanded(
          child: displayData.isEmpty 
          ? const Center(child: Text("暂无持仓，点击右上角 + 添加", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: displayData.length,
              itemBuilder: (context, index) {
                final item = displayData[index];
                bool isUp = item['rate'] >= 0;
                Color valueColor = isUp ? const Color(0xFFFF5252) : const Color(0xFF69F0AE); // 红涨绿跌

                return GestureDetector(
                  onTap: () => _editPosition(item['code'], item['amount']),
                  onLongPress: () => _deleteFund(item['code']),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF424242), // 卡片颜色
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        // 左侧：名称和代码
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['name'], style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text("${item['code']}  持有: ${item['amount'].toInt()}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        // 中间：估值与涨跌
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(item['val'], style: const TextStyle(fontSize: 16, color: Colors.white)),
                              Text("${isUp ? '+' : ''}${item['rate']}%", style: TextStyle(fontSize: 12, color: valueColor)),
                            ],
                          ),
                        ),
                        // 右侧：收益金额
                        Expanded(
                          flex: 2,
                          child: Container(
                            alignment: Alignment.centerRight,
                            child: Text(
                              "${item['profit'] >= 0 ? '+' : ''}${item['profit'].toStringAsFixed(1)}",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor),
                            ),
                          ),
                        ),
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

// ================= 2. AI 助手页面 (简洁对话框) =================

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textCtrl = TextEditingController();
  final List<Map<String, String>> _messages = []; // 'role': 'user'/'ai', 'msg': '...'
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
  }

  void _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _messages.add({'role': 'user', 'msg': text});
      _isLoading = true;
      _textCtrl.clear();
    });

    try {
      // 如果没有 Key
      if (_chat == null) throw Exception("No API Key");

      final response = await _chat!.sendMessage(Content.text(text));
      setState(() {
        _messages.add({'role': 'ai', 'msg': response.text ?? '无回复'});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({'role': 'ai', 'msg': '连接失败，请检查 API Key。'});
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部标题
        Container(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
          child: const Text("AI 投资顾问", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        // 消息列表
        Expanded(
          child: ListView.builder(
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
                  decoration: BoxDecoration(
                    color: isUser ? Colors.blueAccent : const Color(0xFF424242),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(msg['msg']!, style: const TextStyle(color: Colors.white, fontSize: 15)),
                ),
              );
            },
          ),
        ),
        if (_isLoading) const Padding(padding: EdgeInsets.all(8.0), child: CupertinoActivityIndicator(color: Colors.white)),
        // 输入框
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF212121),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "输入问题...",
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF424242),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.send, color: Colors.blueAccent), onPressed: _sendMessage),
            ],
          ),
        ),
      ],
    );
  }
}

// ================= 3. 搜索组件 =================

class FundSearchDelegate extends SearchDelegate {
  final Function(String) onSelect;
  FundSearchDelegate(this.onSelect);

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF303030),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF424242)),
    );
  }

  @override List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  @override Widget buildResults(BuildContext context) => _search();
  @override Widget buildSuggestions(BuildContext context) => _search();

  Widget _search() {
    if (query.length < 2) return const SizedBox();
    return FutureBuilder(
      future: http.get(Uri.parse("http://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx?m=1&key=$query")),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CupertinoActivityIndicator(color: Colors.white));
        try {
          final List datas = json.decode(snapshot.data!.body)['Datas'];
          return ListView.builder(
            itemCount: datas.length,
            itemBuilder: (context, index) {
              final item = datas[index];
              return ListTile(
                title: Text(item['NAME'], style: const TextStyle(color: Colors.white)),
                subtitle: Text(item['CODE'], style: const TextStyle(color: Colors.grey)),
                onTap: () {
                  onSelect(item['CODE']);
                  close(context, null);
                },
              );
            },
          );
        } catch (e) { return const SizedBox(); }
      },
    );
  }
}
