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
| 외부 링크 Custom Tab · 인증 CSV 다운로드 · Android 인쇄 | 인증 토큰 저장 (Rails 세션 쿠키 그대로) |
| WebView 버전 확인 · 네트워크 오류 복구 화면 | 인가 판단 (Pundit 은 서버에만) |

**절대 하지 않는 것**: API 키를 APK 에 넣기, Android 에서 Gemini 직접 호출, 보호자 AI 동의 게이트 우회,
서버의 10MB·매직바이트 검증 완화, OCR 사진을 기기 갤러리에 영구 저장.

## 파일 구성

- `settings.gradle.kts` — 저장소 고정(`google`·`mavenCentral`), `FAIL_ON_PROJECT_REPOS` 로 모듈별 저장소 선언 차단.
- `build.gradle.kts` — **AGP 8.13.2 · Kotlin 2.3.0 단일 고정 지점.** Kotlin 버전은 `dev.hotwire:core` 가
  가져오는 `kotlin-stdlib` 과 맞춰야 한다(현재 2.3.0). 버전 변경 시 AGP·Gradle wrapper·Kotlin 셋을 함께 본다.
- `.mise.toml` — JDK 17 · Gradle 8.14.5 툴체인 고정(재현 가능한 빌드).
- `local.properties` · `keystore.properties` — **gitignored.** 후자가 없으면 `assembleRelease` 가 실패한다.
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
  - `MainActivity.kt` — `REQUIRED_WEBVIEW_VERSION = 120` 상수 보유. 서버의 `allow_browser` Chrome
    임계값과 **같은 값을 유지해야 한다**(한쪽만 바꾸면 406 을 사전 차단하지 못한다).
- `res/values/strings.xml` — **`dev.hotwire:core` 의 문자열 리소스를 같은 이름으로 override 해 한국어화**한다
  (`webview_error_*`, `hotwire_dialog_*`, `hotwire_file_chooser_*`). 원문은 `core-1.3.1.aar` 의
  `res/values/values.xml` 참고. core 버전을 올리면 키가 늘거나 바뀌었는지 확인한다.
- `res/mipmap-*/` — `public/icon.png`(512×512)에서 생성한 적응형 아이콘. 전경은 108dp 캔버스에
  로고를 60% 로 배치해 어떤 런처 마스크에서도 잘리지 않는다.
- `assets/json/path_configuration.json` — 번들 Path Configuration. **원격 장애 시 폴백**이며,
  단일 진실은 `../config/hotwire_native/android_v1.json` 이다(이 파일은 그것의 생성물).

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
| `hotwire_native_app?` 분기 뷰 | native 전용 링크 표현 |

호환성이 깨지는 Path Configuration 변경은 기존 파일을 덮어쓰지 않고 `android_v2.json` 을 **추가**한다.

## CI

**현재 CI 에 포함되어 있지 않다.** `.github/workflows/ci.yml` 은 Ruby 잡 5종(brakeman·importmap audit·
rubocop·test·system test)만 돈다. Android 회귀는 로컬 `./gradlew test lintRelease` 가 유일한 게이트다.
CI 잡 추가는 계획의 P2 항목이다.

> ⚠️ 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 `CLAUDE.md` 와 [`README.md`](README.md) 를 함께 갱신하고,
> 루트 [`../CLAUDE.md`](../CLAUDE.md) 의 디렉토리 인덱스도 확인합니다.
