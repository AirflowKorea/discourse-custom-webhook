# Discourse Custom Webhook

Discourse에서 새 게시글이 작성되면 지정한 웹훅 URL로 알림을 전송하는 플러그인입니다.

## 기능

- 새 토픽/게시글 생성 시 웹훅 전송
- 카테고리별 필터링
- 지연 전송 지원 (게시글 수정 허용)
- 비공개 메시지(PM) 자동 제외

## 설치

### Docker 환경 (권장)

`app.yml`의 `hooks` 섹션에 추가:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/AirflowKorea/discourse-custom-webhook.git
```

그 후 rebuild:

```bash
cd /var/discourse
./launcher rebuild app
```

### 개발 환경

```bash
cd /path/to/discourse/plugins
git clone https://github.com/AirflowKorea/discourse-custom-webhook.git
```

## 설정

**Admin > Settings > Plugins**에서 `custom webhook` 검색:

| 설정 | 설명 | 기본값 |
|------|------|--------|
| `custom_webhook_enabled` | 플러그인 활성화 | `false` |
| `custom_webhook_url` | 웹훅 URL (필수) | - |
| `custom_webhook_categories` | 알림 대상 카테고리 (비어있으면 전체) | - |
| `custom_webhook_delay_seconds` | 전송 지연 시간(초) | `5` |
| `custom_webhook_excerpt_length` | 본문 최대 길이 | `400` |

## 웹훅

### 전송 방식

- **Method**: `POST`
- **Content-Type**: `application/json`
- **Timeout**: 연결 5초, 읽기 10초

### 페이로드 구조

```json
{
  "event": "topic_created",
  "post": {
    "id": 123,
    "post_number": 1,
    "url": "https://forum.example.com/t/hello-world/123",
    "raw": "게시글 원본 내용 (마크다운)...",
    "cooked": "<p>게시글 HTML 내용</p>...",
    "created_at": "2026-01-23T12:00:00Z"
  },
  "topic": {
    "id": 123,
    "title": "Hello World",
    "url": "/t/hello-world/123",
    "category_id": 5,
    "category_name": "공지사항",
    "tags": ["공지", "중요"]
  },
  "user": {
    "id": 1,
    "username": "admin",
    "name": "관리자",
    "avatar_url": "https://forum.example.com/user_avatar/..."
  }
}
```

### 이벤트 타입

| event | 설명 |
|-------|------|
| `topic_created` | 새 토픽의 첫 번째 게시글 |
| `post_created` | 기존 토픽에 대한 답글 |

### 응답 처리

- **2xx**: 성공
- **그 외**: Rails 로그에 경고 기록

## 프로젝트 구조

```
discourse-custom-webhook/
├── plugin.rb                 # 플러그인 메인 파일
│   ├── 메타데이터            # name, version, authors 등
│   ├── DiscourseCustomWebhook # 웹훅 전송 모듈
│   │   ├── send_notification # 알림 전송 로직
│   │   └── build_payload     # JSON 페이로드 생성
│   ├── on(:post_created)     # 이벤트 리스너
│   └── Jobs::CustomWebhookNotify  # 지연 전송 Job
│
└── config/
    ├── settings.yml          # 플러그인 설정 정의
    └── locales/
        ├── server.en.yml     # 영어 번역
        └── server.ko.yml     # 한국어 번역
```

## 동작 흐름

```
1. 사용자가 게시글 작성
          ↓
2. Discourse가 post_created 이벤트 발생
          ↓
3. 플러그인이 이벤트 수신
          ↓
4. 지연 시간 확인
   ├─ 0초: 즉시 전송
   └─ N초: Jobs.enqueue_in으로 지연 실행
          ↓
5. send_notification 실행
   ├─ 활성화 여부 확인
   ├─ URL 존재 여부 확인
   ├─ 게시글 타입 확인 (일반 게시글만)
   ├─ PM 제외
   └─ 카테고리 필터 확인
          ↓
6. build_payload로 JSON 생성
          ↓
7. 별도 Thread에서 HTTP POST 전송
          ↓
8. 응답 확인 및 로깅
```

## 웹훅 수신 서버 예시

### Node.js (Express)

```javascript
app.post('/webhook', express.json(), (req, res) => {
  const { event, post, topic, user } = req.body;

  console.log(`[${event}] ${user.username}: ${topic.title}`);

  // 알림 전송 등 처리

  res.sendStatus(200);
});
```

### Python (Flask)

```python
@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.json

    print(f"[{data['event']}] {data['user']['username']}: {data['topic']['title']}")

    # 알림 전송 등 처리

    return '', 200
```

## 테스트

[webhook.site](https://webhook.site)에서 임시 URL을 발급받아 테스트할 수 있습니다.

1. webhook.site 접속 → 고유 URL 복사
2. Admin에서 해당 URL 설정
3. 테스트 게시글 작성
4. webhook.site에서 수신 확인

## 라이선스

MIT License
