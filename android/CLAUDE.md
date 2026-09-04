# `android/` — Hotwire Native Android 셸

책갈피 Rails 웹앱을 **웹앱과 동시 운영**하기 위한 Android 네이티브 셸입니다.
화면·업무 로직을 Kotlin 으로 재작성하지 않습니다 — **Rails 가 렌더하는 HTML 이 화면의 단일 진실**이고,
이 모듈은 배포된 Rails 화면을 공유 WebView 에 띄우고 **Android 고유 기능만** 담당합니다.

개발자용 빌드·서명 절차는 [`README.md`](README.md), 전체 단계별 계획은
[`../docs/HOTWIRE_NATIVE_ANDROID_PLAN.md`](../docs/HOTWIRE_NATIVE_ANDROID_PLAN.md) 를 봅니다.

## 이 모듈이 하는 일 / 하지 않는 일

| 한다 | 하지 않는다 |
|---|---|
| Hotwire 내비게이션 스택 · Android 뒤로가기 | 화면·폼·업무 규칙 구현 |
| `onShowFileChooser` → 시스템 카메라 · Photo Picker | OCR/AI 호출 (서버 전용) |
| 외부 링크 Custom Tab · 인증 파일 다운로드(엑셀·CSV·PDF) · Android 인쇄 | 인증 토큰 저장 (Rails 세션 쿠키 그대로) |
| WebView 버전 확인 · 네트워크 오류 복구 화면 | 인가 판단 (Pundit 은 서버에만) |

**절대 하지 않는 것**: API 키를 APK 에 넣기, Android 에서 Gemini 직접 호출, 보호자 AI 동의 게이트 우회,
서버의 10MB·매직바이트 검증 완화, OCR 사진을 기기 갤러리에 영구 저장.

## 파일 구성

- `settings.gradle.kts` — 저장소 고정(`google`·`mavenCentral`), `FAIL_ON_PROJECT_REPOS` 로 모듈별 저장소 선언 차단.
- `build.gradle.kts` — **AGP 8.13.2 · Kotlin 2.3.0 단일 고정 지점.** Kotlin 버전은 `dev.hotwire:core` 가
  가져오는 `kotlin-stdlib` 과 맞춰야 한다(현재 2.3.0). 버전 변경 시 AGP·Gradle wrapper·Kotlin 셋을 함께 본다.
- `.mise.toml` — JDK 17 · Gradle 8.14.5 툴체인 고정(재현 가능한 빌드).
- `DEVICE_VERIFICATION.md` — **실기기 검증 체크리스트(Phase 10, 사용자 수행)**. 계획 §11 을 채울 수 있는
  형태로 옮기되 **에뮬레이터에서 이미 실측한 것(🟢)과 아무도 확인한 적 없는 것(🔴)을 구분**한다 —
  🔴 는 대부분 에뮬레이터가 신뢰할 수 없는 영역(실제 카메라·HEIC·고해상도 메모리 압박·시스템 글꼴
  확대·파일 관리자 설치 경로)에서 나온다. 결함 보고 양식과 logcat 명령도 포함.
- `*.apk` · `*.aab` — **gitignored**(`/android/*.apk`). 배포용 사본 두 가지를 같은 빌드에서 복사해 만든다:
  심사 제출본 `chaekgalpi-android-v<versionName>-release.apk` 와 **웹에 올려 내려받게 하는 `index.apk`**.
  파일은 같고 이름만 다르다. 재빌드하면 바이트가 달라지므로 **게시한 SHA-256 도 함께 교체**한다
  ([`README.md`](README.md) §웹 배포용 사본).
- `local.properties` · `keystore.properties` — **gitignored.** 후자가 없으면 `assembleRelease` 가 실패한다.
  서명·제출 절차 전량은 [`README.md`](README.md) §release 서명 에 있다(키 생성·지문 기록·가드 단독 실행·APK 검증 4종·금지 제출물·제출 패키지).
  `verifyReleaseSigning` 은 **4개 값의 존재와 `storeFile` 이 실제로 있는지를 모두** 본다 — 값만 채워져 있고
  파일이 없으면(임시 경로에 만들었다 지운 키 등) 가드가 통과해 버리고 빌드는 한참 뒤 Gradle 내부
  `validateSigningRelease` 에서 원인을 알 수 없는 메시지로 죽는다(실제로 그 상태였다).
- `app/build.gradle.kts` — 모듈 설정 + **release 가드 2종**:
  - `verifyReleaseStartUrl` — URI 파싱으로 scheme=`https`·host=`chaekgalpi.net`·userinfo/port 없음 확인.
    로컬 URL 을 가리키는 release APK 제출 사고를 막는다.
  - `verifyReleaseSigning` — keystore 설정이 없으면 명확히 실패. **debug 키로 폴백하지 않는다.**
  - 둘 다 `assembleRelease`·`bundleRelease` 에 `dependsOn` 으로 물려 있다.
  - `runtime` scope 로만 들어오는 의존성(okhttp·material·constraintlayout)은 코드에서 쓰려면
    **명시 선언으로 scope 를 승격**해야 한다. 새 아티팩트 추가가 아니므로 APK 크기 영향은 없다.

### `app/src/main/`

- `AndroidManifest.xml` — 권한은 **`INTERNET` 하나뿐**. `CAMERA`·저장소 권한을 선언하지 않는다
  (시스템 카메라 Intent + Photo Picker 로 대체). `usesCleartextTraffic=false`, `allowBackup=false`,
  MainActivity 만 launcher 로 export. **화면 회전을 잠그지 않는다**(Galaxy Tab 가로 심사).
- `kotlin/net/chaekgalpi/app/`
  - `ChaekgalpiApplication.kt` — Hotwire 설정 진입점. **User-Agent prefix 만 붙이고 WebView 기본
    Chromium UA 를 덮어쓰지 않는다** — 서버의 `hotwire_native_app?` 판정과
    `allow_browser versions: :modern`(Chrome 120+) 버전 파싱이 **둘 다** 그 문자열에 의존한다.
    라우트 판정 핸들러 등록도 여기서 한다(다운로드 → 신뢰 URL → 라이브러리 기본 3종 순서).
  - `MainActivity.kt` — `REQUIRED_WEBVIEW_VERSION = 120` 상수 보유. 서버의 `allow_browser` Chrome
    임계값과 **같은 값을 유지해야 한다**(한쪽만 바꾸면 406 을 사전 차단하지 못한다).
    `DownloadCoordinator` 를 **onCreate 안에서** 생성한다(ActivityResult 등록 시점 계약).
  - `navigation/`
    - `TrustedUrlPolicy.kt` — URI 파싱 기반 4분기(Internal/BrowserTab/SystemIntent/Reject).
      문자열 `contains`/`endsWith` 를 쓰지 않는다 — 접미 위조를 막을 수 없다.
    - `NativeRouting.kt` — 위 판정을 라우팅 결정(InApp/Fallthrough/Blocked)으로 옮기는 **순수 로직**과,
      세션 쿠키를 실어도 되는지 판정하는 `allowsCredentialedRequest`. 라이브러리 타입에 의존하지
      않아 JVM 단위 테스트로 전수 검증한다. debug 로컬 서버 예외는 origin(scheme+host+port) 일치로만.
    - `TrustedUrlRouteDecisionHandler.kt` / `DownloadRouteDecisionHandler.kt` — 위 판정을 Hotwire 의
      `Router.Decision` 으로 옮기는 얇은 어댑터. 규칙은 여기 두지 않는다.
    - `ChaekgalpiWebFragment.kt` — 네이티브 AppBar 만 제거한 기본 웹 화면 + WebView DownloadListener
      (Activity 의 `DownloadCoordinator` 로 위임하는 안전망) + 파일 선택 WebChromeClient 교체.
  - `web/`
    - `FileChooserCallbackGuard.kt` — 파일 선택 콜백을 **UI 스레드에서 정확히 한 번** 전달하는 순수 로직.
      core 1.3.1 은 둘 다 지키지 않는다 — `BrowseFilesDelegate` 가 IO 디스패처에서 콜백을 부르고,
      새 요청이 오면 이전 `uploadCallback` 을 응답 없이 덮어쓴다(바이트코드 실측).
      에뮬레이터에서 사진 선택 중 **프로세스 abort** 를 1회 실측했고 툼스톤 스택이
      `FileChooserDelegate.sendResult → ValueCallback.onReceiveValue → JNI → SIGTRAP` 이었다.
      재현율이 낮아(약 12회 중 1회) 이 감시자가 그 크래시를 없앤다고 단정하지 않는다.
    - `SafeFileChooserWebChromeClient.kt` — 위 감시자를 끼우는 `HotwireWebChromeClient` 하위 클래스.
      **선택기 UI 자체는 core 것을 그대로 쓴다** — 촬영·선택·캐시 복사·FileProvider 를 core 가 이미
      전부 구현하고 있고, 실측상 시스템 선택기가 카메라와 사진 선택기를 둘 다 제시한다.
      선택기가 이미 떠 있는데 새 요청이 오면 **새 요청을 즉시 닫는다**(이전 콜백을 되살리지 않는다).
  - `files/`
    - `CapturedFileStore.kt` — 사진 찌꺼기를 나이 기준으로 정리한다. core 의 `HotwireFileProvider` 는
      캐시가 아니라 **`filesDir/shared`** 를 쓰고, core 가 청소하는 시점은 `Session` 생성 때 한 번뿐이라
      앱을 켜 둔 채 사진을 여러 장 고르면 **학생 손글씨 원본 사본이 계속 쌓인다**(실측).
      선택기를 열 때마다 생기는 0바이트 `Capture_*.jpg` 도 함께 정리한다.
      **콜백 직후에 지우지 않는다** — WebView 가 `content://` 로 비동기 참조하므로 나이로만 판단한다.
      `MainActivity.onStart()` 에서 돈다(사진 선택기·카메라 동선이 정확히 이 시점을 지난다).
  - `downloads/`
    - `DownloadNaming.kt` — `Content-Disposition`(RFC 6266 `filename*` 우선) → 안전한 파일명. 순수·테스트됨.
    - `AuthenticatedDownloader.kt` — 세션 쿠키를 실어 직접 스트리밍. **리다이렉트를 자동 추적하지 않고**
      매 홉마다 신뢰 호스트를 재검사한다(신뢰 호스트가 외부로 302 를 주면 쿠키가 따라간다).
    - `DownloadCoordinator.kt` — SAF `ACTION_CREATE_DOCUMENT` 로 저장 위치를 **먼저 묻고** 받는다.
      먼저 받아 두면 사용자가 취소해도 서버 감사 원장에 다운로드가 기록되기 때문이다.
- `res/values/strings.xml` — **`dev.hotwire:core` 의 문자열 리소스를 같은 이름으로 override 해 한국어화**한다
  (`webview_error_*`, `hotwire_dialog_*`, `hotwire_file_chooser_*`). 원문은 `core-1.3.1.aar` 의
  `res/values/values.xml` 참고. core 버전을 올리면 키가 늘거나 바뀌었는지 확인한다.
  ⚠️ **lint 가 이 문자열들을 `UnusedResources` 로 표시하는 것은 오탐이다** — 참조가 우리 코드가 아니라 core 안에 있기 때문. Phase 9 에서 AAR 을 풀어 10개 이름이 전부 일치함을 확인했다. **이름이 하나라도 어긋나면 한국어가 조용히 안 나오고 아이가 영어를 본다**(오류도 로그도 없다) — core 업그레이드 때 반드시 AAR 대조로 확인할 것.
- `res/mipmap-*/` — `public/icon.png`(512×512)에서 생성한 적응형 아이콘. 전경은 108dp 캔버스에
  로고를 60% 로 배치해 어떤 런처 마스크에서도 잘리지 않는다.
- `assets/json/path_configuration.json` — 번들 Path Configuration. **원격 장애 시 폴백**이며,
  단일 진실은 `../config/hotwire_native/android_v1.json` 이다(이 파일은 그것의 생성물).
  `BundledPathConfigurationTest` 가 계약을 고정한다 — 특히 **모든 패턴이 Java 정규식으로 컴파일되는지**를 본다.
  서버 쪽 `native_configuration_test.rb` 는 같은 파일을 **Ruby** 정규식으로 검사하는데, 실제 매칭은 Android 가
  하므로 Ruby 에서 유효한 패턴이 Java 에서 예외를 던지면 그 규칙만 앱에서 조용히 사라진다.

### `app/src/debug/`

`AndroidManifest.xml` 이 로컬 Rails 접속용 cleartext 예외를 둔다.
**release 병합 Manifest 에 이 예외가 새지 않는지** `processReleaseMainManifest` 산출물로 검증한다.

## 서버(Rails)와의 계약

이 모듈이 의존하는 서버 표면. **대회 기간 중 삭제·rename 하지 않는다.**

| 서버 자산 | 용도 |
|---|---|
| `GET /configurations/android_v1.json` | 원격 Path Configuration |
| `GET /session/new` | 시작 화면(로그인 선택) |
| `POST /ocr` (`ocr[photo]` multipart) | 사진 OCR 업로드 계약 |
| `GET /reports/:id/photo` | 인증 프록시 사진 |
| `GET /reports/:id/photo/zoom` | **앱 전용** 사진 확대 HTML 화면(웹은 `target="_blank"` 로 바이트를 새 탭에 연다) |
| `GET /teacher/exports/reports_xlsx` · `GET /admin/analytics/export` · `/agree.pdf` | 원격 설정의 `download` 규칙 대상 |
| `hotwire_native_app?` 분기 뷰 | native 전용 링크 표현 |

호환성이 깨지는 Path Configuration 변경은 기존 파일을 덮어쓰지 않고 `android_v2.json` 을 **추가**한다.

**다운로드 경로는 원격 설정이 단일 진실이다.** `download: true` 표시가 빠지면 Turbo 가 내려받기 링크를 방문으로
처리하고, HTML 이 아니라서 앱에는 "화면을 불러오지 못했어요"만 뜬 채 **서버에는 다운로드 감사 로그가 남는다**
(아무도 받지 못한 파일이 내려받아진 것으로 기록). 새 다운로드 경로가 생기면 Kotlin 이 아니라
`config/hotwire_native/android_v1.json` 에 규칙을 추가한다 — APK 재배포 없이 반영되고,
`test/integration/native_configuration_test.rb` 가 실제 라우트와의 정합을 지킨다.

## CI

**현재 CI 에 포함되어 있지 않다.** `.github/workflows/ci.yml` 은 Ruby 잡 5종(brakeman·importmap audit·
rubocop·test·system test)만 돈다. Android 회귀는 로컬 `./gradlew test lintRelease` 가 유일한 게이트다.
CI 잡 추가는 계획의 P2 항목이다(계획 K.4 A-4 "CI 에 Android 레인이 없다").

### 단위 테스트 (`app/src/test/`) — 158건 / 14클래스

`TrustedUrlPolicy`(호스트 접미사 공격 포함)·`NativeRouting`·`DownloadNaming`·`ImagePayload`·
`CapturedFileStore`·`FileChooserCallbackGuard`·`BundledPathConfiguration`. **Espresso(`androidTest`)는
없다** — 계획 K.4 A-7 이 허용한 선택지로, 덮을 항목(런치·로그인·내부이동·뒤로가기·회전 복원·외부 URL·
file chooser 취소)은 Phase 6·8 에서 에뮬레이터 실측으로 기록했고 CI 레인이 없어 작성해도 자동으로 돌지 않는다.

### release 가드 실측 (Phase 9)

`verifyReleaseStartUrl` 이 http·타호스트·**접미사 공격**(`chaekgalpi.net.evil.example`)·포트·userinfo
5종을 각각 정확한 메시지로 차단함을 확인했다.
⚠️ **`assembleRelease` 로 시험하지 말 것** — `validateSigningRelease`(죽은 keystore)가 먼저 실패해
가드가 실행조차 되지 않는데 "BUILD FAILED" 만 보면 통과한 것으로 오인한다. 태스크를 직접 지정한다:
`./gradlew verifyReleaseStartUrl -Pchaekgalpi.releaseStartUrl=<url>`

> ⚠️ 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 `CLAUDE.md` 와 [`README.md`](README.md) 를 함께 갱신하고,
> 루트 [`../CLAUDE.md`](../CLAUDE.md) 의 디렉토리 인덱스도 확인합니다.
