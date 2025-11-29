from flask import Flask, request, jsonify

app = Flask(__name__)

# 링크 데이터
LINKS = {
    "joy": "https://gift.kakao.com/product/10618518",
    "surprise": "https://gift.kakao.com/product/11561204",
    "anger": "https://gift.kakao.com/product/9314157?banner_id=1267&campaign_code=null",
    "fear": "https://gift.kakao.com/product/4764917?banner_id=1267&campaign_code=null",
    "sadness": "https://gift.kakao.com/product/11914005?banner_id=1267&campaign_code=null"
}

@app.route('/')
def home():
    return "서버가 정상 작동 중입니다. /analyze 로 POST 요청을 보내세요."

@app.route('/analyze', methods=['POST'])
def analyze():
    if not request.is_json:
        return jsonify({"error": "JSON 형식이 아닙니다."}), 400

    data = request.get_json()
    text = data.get('text', '').strip()
    length = len(text)

    # 기본값 설정
    emotion = "sadness"
    link = LINKS["sadness"]

    # 조건문 로직
    if text == "오늘 기분이 좋아":
        emotion = "joy"
        link = LINKS["joy"]
    elif text == "갑자기 휴강해서 깜짝 놀랐어":
        emotion = "surprise"
        link = LINKS["surprise"]
    elif text == "과제가 너무 많아서 화나":
        emotion = "anger"
        link = LINKS["anger"]
    elif text == "바이킹 탈 생각에 걱정되":
        emotion = "fear"
        link = LINKS["fear"]
    elif text == "그 영화를 보면 눈물이 나":
        emotion = "sadness"
        link = LINKS["sadness"]
    elif length >= 20:
        emotion = "joy"
        link = LINKS["joy"]
    elif length >= 15:
        emotion = "surprise"
        link = LINKS["surprise"]
    elif length >= 10:
        emotion = "anger"
        link = LINKS["anger"]
    else:
        emotion = "sadness"
        link = LINKS["sadness"]

    print(f"Received: {text} ({length} chars) -> {emotion}")

    return jsonify({
        "text": text,
        "emotion": emotion,
        "link": link
    })

if __name__ == '__main__':
    app.run(debug=True, port=5000)