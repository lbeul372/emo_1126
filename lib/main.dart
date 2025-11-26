import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'emo',
      debugShowCheckedModeBanner: false, // 디버그 배너 제거
      theme: ThemeData(
        // 세련된 크림색 배경
        scaffoldBackgroundColor: const Color(0xFFFFF9E6),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD700), // 따뜻한 노랑
          primary: const Color(0xFFFFB74D), // 포인트 컬러
        ),
        useMaterial3: true,
        // 앱바 스타일 지정
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            // (선택사항) 여기에 귀여운 폰트를 적용하면 더 좋습니다!
            // fontFamily: 'Pretendard', 
          ),
        ),
        // 버튼 기본 스타일 지정
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFB74D),
            foregroundColor: Colors.white,
            elevation: 4,
            shadowColor: const Color(0xFFFFB74D).withOpacity(0.5),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // 아주 둥근 버튼
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
  
  // 초기 안내 문구도 귀엽게 변경
  String _sharedText = "다른 앱에서 텍스트를 공유해주세요";
  
  // 감정 결과 데이터 (초기값은 null)
  Map<String, dynamic>? _emotionData;
  bool _isLoading = false;

  // 감정별 한글 텍스트 및 아이콘 매핑 데이터
  final Map<String, Map<String, dynamic>> _emotionUI = {
    "joy": {
      "text": "happy",
      "icon": Icons.sentiment_very_satisfied_rounded,
      "color": Colors.orangeAccent,
    },
    "surprise": {
      "text": "surprise",
      "icon": Icons.sentiment_satisfied_alt_rounded,
      "color": Colors.purpleAccent,
    },
    "anger": {
      "text": "😡",
      "icon": Icons.sentiment_very_dissatisfied_rounded,
      "color": Colors.redAccent,
    },
    "fear": {
      "text": "🥺",
      "icon": Icons.sentiment_dissatisfied_rounded,
      "color": Colors.blueGrey,
    },
    "sadness": {
      "text": "😢",
      "icon": Icons.sentiment_dissatisfied_rounded,
      "color": Colors.blueAccent,
    },
    // 예외 상황용 기본값
    "default": {
      "text": "🤔",
      "icon": Icons.help_outline_rounded,
      "color": Colors.grey,
    },
  };

  @override
  void initState() {
    super.initState();
    // ... (기존 공유 기능 코드 동일)
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.type == SharedMediaType.text) {
        _handleSharedText(value.first.path);
      }
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });
    
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.type == SharedMediaType.text) {
        _handleSharedText(value.first.path);
      }
    });
  }

  void _handleSharedText(String text) {
    setState(() {
      _sharedText = text;
    });
    _analyzeEmotion(text.trim());
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  Future<void> _analyzeEmotion(String text) async {
    setState(() {
      _isLoading = true;
      _emotionData = null; // 결과 초기화
    });

    const String apiUrl = "https://lbeul372.pythonanywhere.com/analyze";

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"text": text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _emotionData = data; // 서버 데이터 전체 저장
        });
      } else {
        _showErrorSnackBar("서버 오류가 발생했어요 (코드: ${response.statusCode})");
      }
    } catch (e) {
      _showErrorSnackBar("서버와 연결할 수 없어요. 인터넷을 확인해주세요!");
      print(e);
    } finally {
      setState(() {
        _isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    // 현재 감정에 맞는 UI 데이터 가져오기 (없으면 기본값)
    final emotionKey = _emotionData?['emotion'] ?? 'default';
    final uiData = _emotionUI[emotionKey] ?? _emotionUI['default']!;
    final themeColor = _emotionData != null ? uiData['color'] as Color : Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        // 타이틀을 심플하게 'emo'로 변경
        title: const Text('emo'),
      ),
      body: SingleChildScrollView( // 내용이 길어지면 스크롤 가능하게
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 20),
              // 귀여운 말풍선 위젯으로 변경
              MessageBubble(text: _sharedText, color: themeColor),
              const SizedBox(height: 50),

              // 로딩 중일 때
              if (_isLoading) ...[
                const Center(
                  child: CircularProgressIndicator(color: Colors.orangeAccent),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text("마음을 읽고 있어요", style: TextStyle(fontSize: 16, color: Colors.grey)),
                ),
              ]
              // 결과가 나왔을 때
              else if (_emotionData != null) ...[
                // 1. 대문짝만한 감정 아이콘
                Icon(
                  uiData['icon'],
                  size: 120,
                  color: themeColor,
                ),
                const SizedBox(height: 20),
                // 2. 한글 감정 텍스트
                Text(
                  uiData['text'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
                const SizedBox(height: 50),
                // 3. 선물 버튼
                ElevatedButton.icon(
                  onPressed: _launchURL,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor, // 감정별로 버튼 색상 변경
                    shadowColor: themeColor.withOpacity(0.5),
                  ),
                  icon: const Icon(Icons.card_giftcard_rounded, size: 28),
                  label: const Text("🎁 위로의 선물 열어보기"),
                )
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// [NEW] 귀여운 말풍선 위젯 분리
class MessageBubble extends StatelessWidget {
  final String text;
  final Color color;

  const MessageBubble({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 말풍선 꼬리 느낌을 주는 작은 아이콘
        Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: Icon(Icons.format_quote_rounded, color: color.withOpacity(0.5), size: 30),
        ),
        Container(
          margin: const EdgeInsets.only(top: 5),
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(30),
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 5,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.5),
          ),
        ),
      ],
    );
  }
}