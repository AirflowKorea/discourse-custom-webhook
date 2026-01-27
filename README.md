# Discourse Custom Webhook

Discourse에서 새 게시글이 작성되면 지정한 웹훅 URL로 알림을 전송하는 플러그인입니다. 다중 채널과 유연한 필터링 규칙을 지원합니다.

## 주요 기능

- **다중 채널 지원**: 여러 웹훅 엔드포인트를 동시에 관리
- **규칙 기반 필터링**: 카테고리, 태그, 필터 타입으로 정교한 알림 설정
- **필터 옵션**: Watch (전체), Follow (새 토픽만), Mute (차단)
- **테스트 알림**: 토픽을 검색하여 테스트 웹훅 전송
- **웹훅 시크릿**: HTTP 헤더를 통한 인증 지원
- **Discord 호환**: Discord Embed 형식의 페이로드
- **지연 전송**: 게시글 수정을 허용하는 지연 전송 지원
- **비공개 메시지 자동 제외**

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

## 사용법

### 1. 플러그인 활성화

**Admin > Settings > Plugins**에서 `custom webhook` 검색 후 활성화합니다.

| 설정 | 설명 | 기본값 |
|------|------|--------|
| `custom_webhook_enabled` | 플러그인 활성화 | `false` |
| `custom_webhook_delay_seconds` | 전송 지연 시간(초) | `5` |

### 2. 채널 생성

**Admin > Plugins > Custom Webhook**에서 채널을 관리합니다.

채널 설정 항목:
| 항목 | 설명 | 필수 |
|------|------|------|
| 이름 | 채널 식별 이름 | O |
| 웹훅 URL | 알림을 수신할 URL | O |
| 웹훅 시크릿 | `X-Webhook-Secret` 헤더로 전송 | - |
| 메시지 내용 | 페이로드의 `content` 필드 | - |
| 발췌 길이 | 게시글 본문 최대 길이 (100-2000) | - |
| 활성화 | 채널 활성화/비활성화 | - |

### 3. 필터링 규칙 설정

각 채널에 규칙을 추가하여 어떤 게시글이 알림을 트리거할지 설정합니다.

#### 필터 타입

| 필터 | 동작 |
|------|------|
| **Watch** | 새 토픽과 모든 댓글/답글 알림 |
| **Follow** | 새 토픽만 알림 (댓글 제외) |
| **Mute** | 매칭되는 게시글 알림 차단 |

#### 필터링 조건

- **카테고리**: 특정 카테고리 지정 (부모 카테고리 선택 시 하위 카테고리 포함)
- **태그**: 하나 이상의 태그 매칭
- **우선순위**: 높은 값이 먼저 적용 (규칙 간 충돌 시)

#### 규칙 매칭 로직

```
1. 게시글 생성
2. 활성화된 채널 순회
3. 각 채널의 규칙을 우선순위 순으로 확인
4. 첫 번째 매칭 규칙에 따라 처리:
   - Watch/Follow: 알림 전송
   - Mute: 알림 차단
   - 규칙 없음: 모든 게시글 알림
```

### 4. 테스트 알림

채널 목록에서 테스트 버튼을 클릭하여 웹훅을 테스트할 수 있습니다.

- 토픽 제목으로 검색
- 토픽 ID 직접 입력
- 토픽 URL 입력
- 선택하지 않으면 최신 게시글 사용

## 웹훅 페이로드

### 전송 방식

- **Method**: `POST`
- **Content-Type**: `application/json`
- **X-Webhook-Secret**: 시크릿 설정 시 포함
- **Timeout**: 연결 5초, 읽기 10초

### 페이로드 구조 (Discord Embed 호환)

```json
{
  "content": "채널의 메시지 내용",
  "embeds": [{
    "title": "토픽 제목 [카테고리] 태그1, 태그2",
    "color": 5793266,
    "description": "게시글 발췌 내용...",
    "url": "https://forum.example.com/t/topic-slug/123",
    "author": {
      "name": "@username (이름)",
      "url": "https://forum.example.com/u/username",
      "icon_url": "https://forum.example.com/user_avatar/..."
    }
  }]
}
```

### 응답 처리

- **2xx**: 성공
- **그 외**: Rails 로그에 경고 기록

## API 엔드포인트

모든 엔드포인트는 **관리자 권한**이 필요합니다.

### 채널 API

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/admin/plugins/custom-webhook/channels` | 채널 목록 조회 |
| POST | `/admin/plugins/custom-webhook/channels` | 채널 생성 |
| PUT | `/admin/plugins/custom-webhook/channels/:id` | 채널 수정 |
| DELETE | `/admin/plugins/custom-webhook/channels/:id` | 채널 삭제 |
| POST | `/admin/plugins/custom-webhook/channels/:id/test` | 테스트 전송 |

### 규칙 API

| 메서드 | 경로 | 설명 |
|--------|------|------|
| POST | `/admin/plugins/custom-webhook/channels/:channel_id/rules` | 규칙 생성 |
| PUT | `/admin/plugins/custom-webhook/channels/:channel_id/rules/:id` | 규칙 수정 |
| DELETE | `/admin/plugins/custom-webhook/channels/:channel_id/rules/:id` | 규칙 삭제 |

## 프로젝트 구조

```
discourse-custom-webhook/
├── plugin.rb                    # 메인 플러그인 파일
│   ├── Models                   # Channel, Rule 모델
│   ├── Controllers              # 채널/규칙 API 컨트롤러
│   ├── Serializers              # JSON 직렬화
│   └── DiscourseCustomWebhook   # 웹훅 전송 모듈
│
├── admin/assets/javascripts/    # 어드민 프론트엔드
│   ├── templates/               # Handlebars 템플릿
│   ├── controllers/             # Ember 컨트롤러
│   └── routes/                  # 라우트 정의
│
├── assets/stylesheets/          # 스타일시트
│
├── config/
│   ├── settings.yml             # 플러그인 설정
│   └── locales/                 # 다국어 지원 (영어, 한국어)
│
└── db/migrate/                  # 데이터베이스 마이그레이션
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
5. 활성화된 채널 순회
   ├─ 플러그인 활성화 확인
   ├─ 정규 게시글 타입 확인
   ├─ PM 제외
   └─ 규칙 매칭 확인
          ↓
6. 매칭된 채널에 웹훅 전송
          ↓
7. 응답 확인 및 로깅
```

## 웹훅 수신 서버 예시

### Node.js (Express)

```javascript
app.post('/webhook', express.json(), (req, res) => {
  const { content, embeds } = req.body;
  const secret = req.headers['x-webhook-secret'];

  // 시크릿 검증
  if (secret !== process.env.WEBHOOK_SECRET) {
    return res.sendStatus(401);
  }

  console.log(`새 게시글: ${embeds[0].title}`);

  // Discord로 전달하거나 다른 처리

  res.sendStatus(200);
});
```

### Python (Flask)

```python
@app.route('/webhook', methods=['POST'])
def webhook():
    secret = request.headers.get('X-Webhook-Secret')

    if secret != os.environ.get('WEBHOOK_SECRET'):
        return '', 401

    data = request.json
    print(f"새 게시글: {data['embeds'][0]['title']}")

    # 처리 로직

    return '', 200
```

## 테스트

[webhook.site](https://webhook.site)에서 임시 URL을 발급받아 테스트할 수 있습니다.

1. webhook.site 접속 → 고유 URL 복사
2. Admin에서 채널 생성 후 해당 URL 설정
3. 테스트 버튼 클릭 또는 실제 게시글 작성
4. webhook.site에서 수신 확인

## 라이선스

MIT License
