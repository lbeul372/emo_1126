import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'emo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFFF9E6),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD700),
          primary: const Color(0xFFFFB74D),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFB74D),
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late StreamSubscription _intentDataStreamSubscription;
  final TextEditingController _textController = TextEditingController();

  // 상태 변수들
  String _sharedText = "분석할 텍스트를 입력해주세요";
  Map<String, dynamic>? _emotionData; // 현재 화면에 표시 중인 데이터
  bool _isLoading = false;
  String? _userId;
  List<dynamic> _historyLogs = []; // 히스토리 목록

  final String baseUrl = "https://emo-server-final.onrender.com";

  // 감정 UI 데이터
  final Map<String, Map<String, dynamic>> _emotionUI = {
    "joy": { "text": "Happy 😊", "icon": Icons.sentiment_very_satisfied_rounded, "color": Colors.orange },
    "surprise": { "text": "Surprise 😲", "icon": Icons.sentiment_satisfied_alt_rounded, "color": Colors.purpleAccent },
    "anger": { "text": "Anger 😡", "icon": Icons.sentiment_very_dissatisfied_rounded, "color": Colors.redAccent },
    "fear": { "text": "Fear 😨", "icon": Icons.sentiment_dissatisfied_rounded, "color": Colors.blueGrey },
    "sadness": { "text": "Sadness 😢", "icon": Icons.sentiment_dissatisfied_rounded, "color": Colors.blueAccent },
    "hurt": { "text": "Hurt 💔", "icon": Icons.heart_broken, "color": Colors.pinkAccent },
    "default": { "text": "Thinking... 🤔", "icon": Icons.help_outline_rounded, "color": Colors.grey },
  };

  @override
  void initState() {
    super.initState();
    _loadUserId();

    // 공유하기 텍스트 수신 처리
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.type == SharedMediaType.text) {
        _handleNewText(value.first.path);
      }
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.type == SharedMediaType.text) {
        _handleNewText(value.first.path);
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  // 1. 사용자 ID 로드 및 히스토리 가져오기
  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('user_uuid');

    if (storedId == null) {
      storedId = const Uuid().v4();
      await prefs.setString('user_uuid', storedId);
    }

    setState(() {
      _userId = storedId;
    });
    
    // ID 로드 후 히스토리 불러오기
    _fetchHistory();
  }

  // 2. 히스토리 목록 불러오기 (GET)
  Future<void> _fetchHistory() async {
    if (_userId == null) return;
    try {
      final response = await http.get(Uri.parse("$baseUrl/history/$_userId"));
      if (response.statusCode == 200) {
        setState(() {
          _historyLogs = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      print("History fetch error: $e");
    }
  }

  // 3. 히스토리 삭제 (DELETE)
  Future<void> _deleteHistory(int logId) async {
    try {
      final response = await http.delete(Uri.parse("$baseUrl/history/$logId"));
      if (response.statusCode == 200) {
        _fetchHistory(); // 목록 갱신
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("삭제되었습니다.")),
        );
        // 만약 현재 보고 있는 화면이 삭제된 그 로그라면 초기화
        if (_emotionData != null && _emotionData!['log_id'] == logId) {
           setState(() {
             _emotionData = null;
             _sharedText = "분석할 텍스트를 입력해주세요";
           });
        }
      }
    } catch (e) {
      print("Delete error: $e");
    }
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    _textController.dispose();
    super.dispose();
  }

  // 뒤로가기 핸들러
  Future<bool> _onWillPop() async {
    if (_emotionData != null) {
      setState(() {
        _emotionData = null;
        _sharedText = "분석할 텍스트를 입력해주세요";
      });
      return false;
    }
    return true;
  }

  // 새 텍스트 처리 (분석 요청)
  void _handleNewText(String text) {
    if (text.trim().isEmpty) return;

    setState(() {
      _sharedText = text;
      _emotionData = null;
    });

    FocusScope.of(context).unfocus();
    _textController.clear();
    _analyzeEmotion(text.trim());
  }

  // 4. 감정 분석 요청 (POST)
  Future<void> _analyzeEmotion(String text) async {
    if (_userId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/analyze"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "text": text,
          "user_id": _userId 
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _emotionData = data;
        });
        _fetchHistory(); // 분석 후 히스토리 갱신
      } else {
        _showErrorSnackBar("서버 오류: ${response.statusCode}");
      }
    } catch (e) {
      _showErrorSnackBar("서버 연결 실패. 배포 중일 수 있습니다.");
      print(e);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 5. 버그 리포트 (수정) 요청 (POST)
  Future<void> _reportBug(String correctEmotion) async {
    if (_emotionData == null) return;
    
    final int logId = _emotionData!['log_id'];

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/report"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "log_id": logId,
          "user_label": correctEmotion
        }),
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(utf8.decode(response.bodyBytes));
        
        // 화면 즉시 갱신
        setState(() {
          _emotionData!['emotion'] = resData['new_emotion'];
          _emotionData!['link'] = resData['new_link'];
          _emotionData!['is_corrected'] = true;
        });
        
        _fetchHistory(); // 히스토리 목록도 갱신
        
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("피드백 반영 완료! '${_emotionUI[correctEmotion]!['text']}'로 수정되었습니다.")),
        );
      }
    } catch (e) {
      _showErrorSnackBar("오류 발생: $e");
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _launchURL() async {
    if (_emotionData == null || _emotionData!['link'] == null) return;
    final Uri url = Uri.parse(_emotionData!['link']);
    if (!await launchUrl(url)) {
      _showErrorSnackBar('링크를 열 수 없어요');
    }
  }

  // 상세 모달
  void _showDetailsModal() {
    // 수정된 기록이면 상세 보기 불가
    if (_emotionData != null && _emotionData!['is_corrected'] == true) return;
    if (_emotionData == null || _emotionData!['probabilities'] == null) return;

    final Map<String, dynamic> probs = _emotionData!['probabilities'];
    final sortedEntries = probs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 혼합 감정 메시지
    bool isMixedEmotion = false;
    String mixedMessage = "";
    if (sortedEntries.length >= 2) {
      final diff = sortedEntries[0].value - sortedEntries[1].value;
      if (diff < 10.0) {
        isMixedEmotion = true;
        mixedMessage =
            "${_emotionUI[sortedEntries[0].key]!['text']}와 ${_emotionUI[sortedEntries[1].key]!['text']} 사이에서 고민되네요!";
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.all(24),
                child: ListView(
                  controller: controller,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const Text("상세 감정 분석", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 20),

                    if (isMixedEmotion)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9E6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFD700)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_rounded, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(child: Text(mixedMessage, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ),

                    ...sortedEntries.map((entry) {
                      final emotionKey = entry.key;
                      final prob = entry.value;
                      final uiData = _emotionUI[emotionKey] ?? _emotionUI['default']!;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(children: [Icon(uiData['icon'], size: 20, color: uiData['color']), const SizedBox(width: 8), Text(uiData['text'], style: const TextStyle(fontWeight: FontWeight.bold))]),
                                Text("${prob.toStringAsFixed(1)}%", style: const TextStyle(color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Stack(
                              children: [
                                Container(height: 8, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4))),
                                FractionallySizedBox(widthFactor: prob / 100, child: Container(height: 8, decoration: BoxDecoration(color: uiData['color'], borderRadius: BorderRadius.circular(4)))),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    const Divider(height: 40),

                    // 리포트 UI
                    ExpansionTile(
                      title: const Text("혹시 다른 감정인가요?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                      subtitle: const Text("클릭하여 리포트하기", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      initiallyExpanded: false,
                      shape: const Border(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 20),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _emotionUI.keys
                                .where((k) => k != 'default')
                                .map((key) => ChoiceChip(
                                      label: Text(_emotionUI[key]!['text'].split(' ')[0]),
                                      selected: false,
                                      onSelected: (bool selected) {
                                        Navigator.pop(context);
                                        _reportBug(key);
                                      },
                                      backgroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey[300]!)),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emotionKey = _emotionData?['emotion'] ?? 'default';
    final uiData = _emotionUI[emotionKey] ?? _emotionUI['default']!;
    final themeColor = _emotionData != null ? uiData['color'] as Color : const Color(0xFFFFB74D);
    final bool isCorrected = _emotionData?['is_corrected'] ?? false; // 수정 여부 확인

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(title: const Text('emo')),
        // 왼쪽 사이드바
        drawer: Drawer(
          backgroundColor: const Color(0xFFFFF9E6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("History", style: TextStyle(fontSize: 20, 
                    fontWeight: FontWeight.bold)),
                    IconButton(onPressed: _fetchHistory, icon: const Icon(Icons.refresh, color: Colors.grey))
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _historyLogs.isEmpty
                    ? const Center(child: Text("아직 기록이 없어요", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _historyLogs.length,
                        itemBuilder: (context, index) {
                          final log = _historyLogs[index];
                          final logEmotion = log['emotion'];
                          final logUi = _emotionUI[logEmotion] ?? _emotionUI['default']!;
                          final bool logCorrected = log['is_corrected'] ?? false;

                          return Dismissible(
                            key: Key(log['log_id'].toString()),
                            confirmDismiss: (direction) async => false,
                            child: ListTile(
                              leading: Icon(logUi['icon'], color: logUi['color']),
                              title: Text(
                                log['text'], 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500)
                              ),
                              subtitle: Row(
                                children: [
                                  Text(log['date'].substring(5), style: const TextStyle(fontSize: 12)),
                                  if (logCorrected) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                                      child: const Text("수정됨", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                    )
                                  ]
                                ],
                              ),
                              onTap: () {
                                // 히스토리 클릭 시 해당 데이터 로드
                                setState(() {
                                  _emotionData = log;
                                  _sharedText = log['text'];
                                });
                                Navigator.pop(context);
                              },
                              onLongPress: () {
                                showDialog(
                                  context: context, 
                                  builder: (context) => AlertDialog(
                                    title: const Text("기록 삭제"),
                                    content: const Text("이 기록을 삭제하시겠습니까?"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteHistory(log['log_id']);
                                        }, 
                                        child: const Text("삭제", style: TextStyle(color: Colors.red))
                                      ),
                                    ],
                                  )
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(30.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: 10),
                          MessageBubble(text: _sharedText, color: themeColor),
                          const SizedBox(height: 40),

                          if (_isLoading) ...[
                            const SizedBox(height: 50),
                            const Center(child: CircularProgressIndicator(color: Color(0xFFFFB74D))),
                            const SizedBox(height: 20),
                            const Center(child: Text("감정을 분석 중이에요...", style: TextStyle(color: Colors.grey))),
                          ] else if (_emotionData != null) ...[
                            Icon(uiData['icon'], size: 120, color: themeColor),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  uiData['text'],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: themeColor),
                                ),
                                if (isCorrected) ...[
                                  const SizedBox(width: 8),
                                  const Tooltip(
                                    message: "사용자 피드백으로 수정된 결과입니다.",
                                    child: Icon(Icons.edit_note_rounded, color: Colors.grey, size: 20),
                                  )
                                ]
                              ],
                            ),
                            const SizedBox(height: 40),
                            ElevatedButton.icon(
                              onPressed: _launchURL,
                              style: ElevatedButton.styleFrom(backgroundColor: themeColor),
                              icon: const Icon(Icons.card_giftcard_rounded, size: 24),
                              label: const Text("🎁 위로의 선물 열어보기"),
                            ),
                            const SizedBox(height: 12),
                            // 수정된 결과라면 버튼 비활성화 
                            if (!isCorrected)
                              TextButton(
                                onPressed: _showDetailsModal,
                                child: Text("더 자세히 알아보기", style: TextStyle(color: Colors.grey[600], decoration: TextDecoration.underline)),
                              )
                            else
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text("※ 수정된 감정입니다.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                ),
                              )
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 10, offset: const Offset(0, -2))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(30)),
                          child: TextField(
                            controller: _textController,
                            style: const TextStyle(fontSize: 16),
                            decoration: const InputDecoration(hintText: "분석할 텍스트를 입력해주세요", hintStyle: TextStyle(color: Colors.grey, fontSize: 14), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 14)),
                            onSubmitted: _handleNewText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: const BoxDecoration(color: Color(0xFFFFB74D), shape: BoxShape.circle),
                        child: IconButton(icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white), onPressed: () => _handleNewText(_textController.text)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String text;
  final Color color;
  const MessageBubble({super.key, required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.format_quote_rounded, color: color.withOpacity(0.5), size: 40),
        Container(
          margin: const EdgeInsets.only(top: 5),
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
            boxShadow: [BoxShadow(color: color.withOpacity(0.1), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.4)),
        ),
      ],
    );
  }
}