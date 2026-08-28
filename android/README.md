# 책갈피 Android (Hotwire Native 셸)

Rails 웹앱 「책갈피」를 **웹앱과 동시 운영**하기 위한 Android 네이티브 셸입니다.
화면과 업무 로직은 전부 서버(`https://chaekgalpi.net`)가 렌더하는 Turbo/Stimulus HTML이고,
이 프로젝트는 내비게이션·파일 선택·다운로드·인쇄 같은 **Android 고유 기능만** 담당합니다.

전체 설계·단계별 계획은 [`../docs/HOTWIRE_NATIVE_ANDROID_PLAN.md`](../docs/HOTWIRE_NATIVE_ANDROID_PLAN.md) 참고.

---

## 툴체인 (고정)

| 항목 | 버전 | 비고 |
|---|---|---|
| JDK | Temurin **17** | `.mise.toml` 로 고정 |
| Gradle | **8.14.5** | Wrapper 로 고정. `./gradlew` 만 사용 |
| AGP | **8.13.2** | Gradle 8.13+ 요구 |
| Kotlin | **2.3.0** | `dev.hotwire:core` 의 `kotlin-stdlib 2.3.0` 에 맞춤 |
| compileSdk / targetSdk | **35** | |
| minSdk | **28** | Hotwire Native 하한. 기준 기기 SM-P610 은 API 29 |
| Hotwire Native | **1.3.1** | `core` + `navigation-fragments` |

> 버전을 올릴 때는 **AGP · Gradle wrapper · Kotlin** 셋을 함께 검토한다.
> 동적 버전(`1.+`, `latest.release`)은 쓰지 않는다 — 재현 가능한 빌드가 원칙이다.

### 최초 설정

```bash
mise install                      # android/.mise.toml 의 java·gradle
# Android SDK (한 번만)
#   ~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager \
#     "platforms;android-35" "build-tools;35.0.0" "platform-tools"
echo "sdk.dir=$HOME/Android/Sdk" > local.properties   # 커밋하지 않는다
```

---

## 빌드

```bash
./gradlew assembleDebug     # 개발용. START_URL 은 http://10.0.2.2:3000 (에뮬레이터→호스트 Rails)
./gradlew test              # JVM 단위 테스트
./gradlew lintRelease
```

실기기 debug 빌드에서 LAN 의 Rails 를 붙이려면:

```bash
./gradlew assembleDebug -Pchaekgalpi.debugStartUrl=http://192.168.0.10:3000
```

### 시작 URL 규칙

| build type | START_URL | 비고 |
|---|---|---|
| debug | `http://10.0.2.2:3000` (덮어쓰기 가능) | `src/debug/AndroidManifest.xml` 이 cleartext 를 허용 |
| release | `https://chaekgalpi.net` | **고정.** 아래 가드가 강제 |

`assembleRelease` 는 두 검증을 통과해야만 실행된다.

- **`verifyReleaseStartUrl`** — URI 파싱으로 scheme=`https`, host=`chaekgalpi.net`, userinfo·port 없음을 확인.
  문자열 `contains` 비교를 쓰지 않는다.
- **`verifyReleaseSigning`** — `keystore.properties` 가 없으면 **명확히 실패**한다. debug 키로 폴백하지 않는다.

가드가 실제로 동작하는지는 소스를 고치지 말고 속성으로 시험한다.

```bash
./gradlew verifyReleaseStartUrl -Pchaekgalpi.releaseStartUrl=http://localhost:3000   # 실패해야 정상
./gradlew verifyReleaseStartUrl                                                       # 통과해야 정상
```

---

## release 서명

### 1. 키 생성 (최초 1회, 저장소 밖에서)

```bash
keytool -genkeypair -v \
  -keystore ~/chaekgalpi-release.jks \
  -alias chaekgalpi -keyalg RSA -keysize 4096 -validity 10950 \
  -dname "CN=<이름>, O=<소속>, L=<지역>, C=KR"
```

### 2. `android/keystore.properties` (gitignored)

```properties
storeFile=/home/<user>/chaekgalpi-release.jks
storePassword=<비밀번호>
keyAlias=chaekgalpi
keyPassword=<비밀번호>
```

> ⚠️ **패키지명(`net.chaekgalpi.app`)과 서명 키는 앱의 신원이다.**
> 한 번 배포한 뒤 패키지명을 바꾸거나 키를 잃으면 기존 설치본 위에 업데이트할 수 없다.
> keystore 파일과 비밀번호는 **암호화 보관 1부 + 오프라인 백업 1부**를 두고,
> 인증서 SHA-256 fingerprint 를 따로 기록한다. 저장소·APK 제출 폴더·문서 zip 에 넣지 않는다.

### 3. 빌드·검증

```bash
./gradlew clean test lintRelease assembleRelease
cp app/build/outputs/apk/release/app-release.apk chaekgalpi-android-v1.0.0-release.apk

apksigner verify --verbose --print-certs chaekgalpi-android-v1.0.0-release.apk
sha256sum chaekgalpi-android-v1.0.0-release.apk
```

### versionCode 정책

- release 후보마다 **`versionCode` 를 +1** 한다. 되돌리지 않는다.
- 배포한 APK 보다 낮은 `versionCode` 로는 일반 업데이트 설치가 되지 않는다.
- `versionName` 은 사람이 읽는 값(`1.0.0`), `versionCode` 는 단조 증가하는 정수다.

---

## 보안 경계 (변경 전 반드시 확인)

- 권한은 **`INTERNET` 하나뿐**이다. `CAMERA`·`READ_MEDIA_IMAGES`·저장소 권한을 선언하지 않는다
  (시스템 카메라 Intent + Photo Picker 로 대체).
- **API 키를 APK 에 넣지 않는다.** Gemini·Claude·네이버·정보나루 키는 Rails 서버만 가진다.
- 상위 화면 WebView 탐색은 `chaekgalpi.net` / `www.chaekgalpi.net` 만 신뢰한다.
  검사는 **URI 파싱 후 scheme·host 정확 비교**로 한다.
- 임의의 `addJavascriptInterface` 를 만들지 않는다. 네이티브 통신은 Hotwire Bridge Component 만 쓴다.
- release 는 `usesCleartextTraffic=false`, `debuggable=false`, WebView debugging off, Hotwire 로그 off.
- 촬영한 손글씨 사진은 **앱 전용 cache 에만** 두고 UUID 파일명을 쓴다. 갤러리에 저장하지 않는다.
- Logcat 에 사진 URI·파일 경로·쿠키·CSV 본문을 남기지 않는다.

---

## CI

**이 프로젝트는 현재 CI 에 포함되어 있지 않다.** `.github/workflows/ci.yml` 은 Ruby 잡 5종만 돈다.
Android 회귀는 **로컬 `./gradlew test lintRelease` 가 유일한 게이트**다.

CI 잡 추가(`assembleDebug` + `test`)는 계획의 P2 항목으로 등록되어 있다.
추가할 때는 SDK 설치로 CI 시간·비용이 늘어나는 것을 함께 검토한다.

---

## 디렉터리

```text
android/
├─ settings.gradle.kts      저장소 고정(google·mavenCentral), FAIL_ON_PROJECT_REPOS
├─ build.gradle.kts         AGP·Kotlin 플러그인 버전 단일 고정 지점
├─ gradle.properties        AndroidX·병렬·캐시
├─ .mise.toml               JDK·Gradle 툴체인 고정
├─ local.properties         SDK 경로 (gitignored)
├─ keystore.properties      서명 키 (gitignored, 없으면 release 실패)
└─ app/
   ├─ build.gradle.kts      모듈 설정 + release 가드 2종
   └─ src/
      ├─ main/
      │  ├─ AndroidManifest.xml       권한 INTERNET 하나, allowBackup=false
      │  ├─ assets/json/              번들 Path Configuration (원격 장애 시 폴백)
      │  ├─ kotlin/net/chaekgalpi/app/
      │  └─ res/                      아이콘·테마·한국어 문자열(core 리소스 override 포함)
      ├─ debug/AndroidManifest.xml    로컬 Rails 용 cleartext 예외 (release 에 병합되지 않음)
      ├─ test/                        JVM 단위 테스트
      └─ androidTest/                 Espresso
```
