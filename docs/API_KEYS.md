# 「책갈피」 API 키 가이드

> **목적**: 이 앱이 사용하는 외부 API 키가 **무엇이며**, **어디에 어떻게 주입**하고, **키가 없을 때 어떻게 동작**하는지 정리한다.
> 최종 수정: 2026-07-07

---

## 0. 핵심 요약 (TL;DR)

- 앱은 **오직 Rails 암호화 credentials** 에서만 키를 읽는다. ENV 변수는 앱 코드가 직접 읽지 않는다(§5 참고).
- 키 주입 = **`bin/rails credentials:edit`** 로 `config/credentials.yml.enc` 를 편집. `config/master.key`(개발) / `RAILS_MASTER_KEY`(프로덕션)로 복호화된다.
- **키가 하나도 없어도 앱은 완전히 동작한다.** 각 기능이 폴백 경로로 자동 전환된다(사진 OCR만 비활성). 대회 데모·오프라인 시연이 가능하도록 설계되었다.
- 키는 **절대 코드·DB(app_settings)·git 에 커밋하지 않는다**(§5, RAILS_PLAN §15).

---

## 1. 필요한 API 키 목록

| credentials 키 | 발급처 | 켜지는 기능 | 없을 때(기본) 폴백 |
|---|---|---|---|
| `gemini.api_key` | **Google AI Studio** (aistudio.google.com) | ① 손글씨 사진 **OCR**<br>② AI **5축 첨삭**<br>③ 진위·표절 보조<br>④ 퀴즈 초안 생성 | ① 사진 OCR **모드 비활성**(키보드·원고지만)<br>② **규칙기반 첨삭**으로 무중단 채점<br>③ 중립 결과<br>④ 템플릿 기반 오프라인 퀴즈 |
| `kakao.rest_key` | **Kakao Developers** (developers.kakao.com) | 도서 검색(1순위) | Naver로 폴백 → 둘 다 없으면 로컬 캐시(`books` LIKE 검색) |
| `naver.client_id`<br>`naver.client_secret` | **Naver Developers** (developers.naver.com) — 검색 API | 도서 검색(Kakao 실패 시 2순위) | 로컬 캐시 검색으로 폴백 |
| `data4library.api_key` | **정보나루** (data4library.kr) | 사서 대시보드 **인기대출 동기화** | CSV 업로드로 대체(`import_csv`) |

> **하나의 Gemini 키가 4개 AI 기능을 모두 켠다.** 도서 검색은 Kakao→Naver 순으로 시도하므로 둘 중 하나만 있어도 된다.

### 1.1 각 키가 읽히는 코드 위치

| 키 | 읽는 파일 | 판정 |
|---|---|---|
| `gemini.api_key` | `app/services/ai/gemini_client.rb` | `Ai::GeminiClient.available?` |
| `kakao.rest_key` / `naver.*` | `app/services/books/search_service.rb` | `Books::SearchService#available?` |
| `data4library.api_key` | `app/services/library/data4library_service.rb` | `Library::Data4libraryService.available?` |

---

## 2. credentials 구조

`bin/rails credentials:edit` 로 열리는 YAML 은 다음 구조다(값이 비어 있으면 폴백 동작):

```yaml
# 프로덕션 시크릿 (API 키 아님, 반드시 유지)
secret_key_base: "…(자동 생성됨)…"

# 외부 API 키 — 값이 "" 이면 폴백 경로가 기본 동작
gemini:
  api_key: ""
kakao:
  rest_key: ""
naver:
  client_id: ""
  client_secret: ""
data4library:
  api_key: ""
```

> ⚠️ `secret_key_base` 는 프로덕션 부팅에 필수다. **삭제하지 말 것.**

---

## 3. 키 주입 방법

### 3.1 개발 환경 (로컬)

```bash
# 편집기가 열리면 위 구조의 "" 자리에 실제 키를 채워 저장
bin/rails credentials:edit
```

- 저장하면 `config/credentials.yml.enc`(암호문)가 갱신되고, `config/master.key`(gitignore됨)로 복호화된다.
- `EDITOR` 가 설정돼 있어야 한다. 예: `EDITOR="code --wait" bin/rails credentials:edit` 또는 `EDITOR=vim bin/rails credentials:edit`.

### 3.2 프로덕션 환경 (DigitalOcean · Kamal 2)

프로덕션에서도 **동일한 credentials 파일**을 사용한다. 서버는 `RAILS_MASTER_KEY` 로 이를 복호화한다.

1. **로컬에서** 실제 키를 credentials 에 넣는다(위 3.1). `config/credentials.yml.enc` 는 git 에 커밋되지만 **암호문**이라 안전하다.
2. `config/master.key` 의 내용을 서버의 `RAILS_MASTER_KEY` 로 주입한다. 이미 `.kamal/secrets` 가 이를 처리한다:
   ```bash
   # .kamal/secrets (git-safe, 이미 설정됨)
   RAILS_MASTER_KEY=$(cat config/master.key)
   ```
3. 배포:
   ```bash
   kamal setup      # 최초 1회
   kamal deploy     # 이후 배포
   ```

즉 **프로덕션에 API 키를 넣는 절차 = `credentials:edit` 로 키를 넣고 재배포**. 서버에 별도로 키를 넣을 필요가 없다(마스터 키만 있으면 됨).

---

## 4. 주입 확인 (검증)

키가 제대로 인식되는지 확인:

```bash
# 개발
bin/rails runner '
  puts "Gemini      : #{Ai::GeminiClient.available?}"
  puts "도서검색     : #{Books::SearchService.new.available?}"
  puts "정보나루     : #{Library::Data4libraryService.available?}"
'
```

- 모두 `false` → 폴백 경로로 동작(정상, 데모 가능).
- `true` → 해당 실제 API 가 호출된다.

프로덕션에서 확인:

```bash
kamal app exec 'bin/rails runner "puts Ai::GeminiClient.available?"'
```

---

## 5. 보안 규칙 (RAILS_PLAN §15)

- **API 키는 서버에만.** credentials(암호화) 또는 ENV. 클라이언트(브라우저) 노출 금지 — 모든 외부 호출은 서버 서비스 객체 경유.
- **DB(app_settings)에 키 저장 금지.** `AppSetting.set` 은 `*_api_key`/`*_key`/`*_secret`/`gemini`/`kakao`/`naver`/`data4library` 형태의 키를 **거부**한다(`app/models/app_setting.rb`).
- **`config/master.key` 는 절대 git 에 커밋하지 않는다**(`.gitignore` 에 포함됨). 팀원에게는 별도 채널(패스워드 매니저 등)로 전달.
- `config/credentials.yml.enc`(암호문)는 커밋해도 안전하다.
- **연령제한 준수**: 학생이 외부 AI 를 직접 호출하지 않고 반드시 서버를 경유하도록 구조적으로 강제된다(대회 등외 방지 절대요건).

---

## 6. 부록 — deploy.yml 의 ENV 시크릿 항목에 대하여

`config/deploy.yml` 의 `env.secret` 에는 `RAILS_MASTER_KEY` 외에 `GEMINI_API_KEY`·`KAKAO_REST_KEY`·`NAVER_CLIENT_ID`·`NAVER_CLIENT_SECRET`·`DATA4LIBRARY_KEY` 가 선언되어 있고, `.kamal/secrets` 가 이를 셸 ENV(`${VAR}`, 미설정 시 빈 값)에서 주입한다.

> **중요**: 현재 앱 코드는 이 키들을 **credentials 에서 읽으며 ENV 를 직접 읽지 않는다**(§1.1). 따라서 deploy.yml 의 ENV 항목은 **운영자가 ENV 로 키를 공급하고 싶을 때를 위한 예약 후크**이며, 지금은 실동작에 영향을 주지 않는다. 실제 주입은 **§3 의 credentials 경로**를 사용하라.
>
> ENV 방식을 실제로 쓰고 싶다면, 각 서비스의 `initialize(api_key: …)` 기본값을 `ENV.fetch("GEMINI_API_KEY", Rails.application.credentials.dig(:gemini, :api_key))` 형태로 확장하면 된다(선택 사항, 코드 변경 필요).

---

## 참고 문서
- 설계·보안 규정: [`RAILS_PLAN.md`](./RAILS_PLAN.md) §9(외부 서비스), §15(보안)
- 배포 절차: [`IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md) Phase 8
