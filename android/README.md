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
  -dname "CN=Chaekgalpi, O=Chaekgalpi, C=KR"
```

> ⚠️ **`-dname` 에 실명·학교명·지역을 넣지 않는다.** 이 값들은 APK 에서 누구나 읽을 수 있고
> (`apksigner verify --print-certs` → `Signer #1 certificate DN: ...`), **한 번 만들면 바꿀 수 없다**
> (바꾸려면 키를 새로 만들어야 하고 그러면 앱 신원이 달라진다). 대회 요강이 **시·도명·학교명·
> 출품자명** 노출을 금지하는데(`app/views/shared/_contest_banner.html.erb`), 제출물인 APK 에서
> 그대로 읽히는 것은 굳이 감수할 이유가 없다.
>
> **자체 서명 인증서라 이 값을 검증하는 주체가 아무도 없다** — Android 는 DN 을 보지 않고,
> 업데이트 가능 여부는 오직 **키가 같은지**로만 판단한다. 실명을 넣어 얻는 이득이 0이다.
>
> | 항목 | 뜻 | 이 프로젝트에서 |
> |---|---|---|
> | `CN` | Common Name (주 식별자) | 앱 이름 `Chaekgalpi` |
> | `O` | Organization (조직) | 앱 이름 `Chaekgalpi` |
> | `C` | Country — **2글자 ISO 코드** | `KR` (`KOR`·`Korea` 아님) |
> | `L` | Locality (도시) | **생략한다** — 지역이 곧 시·도 단서다 |
>
> 한글(`CN=책갈피`)도 정상 저장·복원되는 것을 확인했으나, 도구에 따라 인코딩 표시가 어긋날 수
> 있어 ASCII 를 권한다.

키를 만든 직후 **인증서 지문을 기록**한다. 나중에 "이 APK 가 그 키로 서명된 게 맞나"를
확인하는 유일한 근거다.

```bash
keytool -list -v -keystore ~/chaekgalpi-release.jks -alias chaekgalpi | grep "SHA256:"
```

### 2. `android/keystore.properties` (gitignored)

> ⚠️ **이 파일은 이미 존재할 수 있다.** 새로 만드는 것이 아니라 **열어서 `storeFile` 을
> 실제 키 경로로 바꾸는** 작업이다. 지금 저장소에 있는 값은 개발 중 만들었다 지운 임시 키의
> 경로를 가리키고 있어서 `verifyReleaseSigning` 이 실패한다 — **실제 키가 생길 때까지
> 시끄럽게 실패하는 것이 의도된 상태다.**

```properties
storeFile=/home/<user>/chaekgalpi-release.jks
storePassword=<비밀번호>
keyAlias=chaekgalpi
keyPassword=<비밀번호>
```

설정이 맞는지 빌드 전에 따로 확인할 수 있다(서명 가드만 단독 실행).

```bash
./gradlew verifyReleaseSigning
# 성공: "release 서명 설정 확인됨: <경로>"
# 실패: 어떤 경로가 비었는지 메시지가 지목한다
```

> ⚠️ **패키지명(`net.chaekgalpi.app`)과 서명 키는 앱의 신원이다.**
> 한 번 배포한 뒤 패키지명을 바꾸거나 키를 잃으면 기존 설치본 위에 업데이트할 수 없다.
> keystore 파일과 비밀번호는 **암호화 보관 1부 + 오프라인 백업 1부**를 두고,
> 인증서 SHA-256 fingerprint 를 따로 기록한다. 저장소·APK 제출 폴더·문서 zip 에 넣지 않는다.

### 3. 빌드·검증

> ⚠️ **도구 두 개가 그냥은 안 돈다.** 실제로 겪은 순서대로 적는다.
> - `apksigner`·`aapt2` 는 **PATH 에 없다**(SDK build-tools 안에 있다).
> - `apksigner` 는 셸 래퍼라 **`java` 가 PATH 에 있어야 한다.** 없으면
>   `exec: java: not found` 로 죽는데, **종료 코드는 0 이라** 파이프에 물리면 조용히 빈 출력만 남는다.
>
> ```bash
> export PATH="$JAVA_HOME/bin:$PATH"                                   # java 없으면 apksigner 가 죽는다
> export BT=$(find "$ANDROID_HOME/build-tools" -maxdepth 1 -type d | sort -V | tail -1)
> echo "$BT"   # 예: /home/<user>/Android/Sdk/build-tools/35.0.0
> ```

```bash
./gradlew clean test lintRelease assembleRelease
cp app/build/outputs/apk/release/app-release.apk chaekgalpi-android-v1.0.1-release.apk

"$BT/apksigner" verify --verbose --print-certs chaekgalpi-android-v1.0.1-release.apk
sha256sum chaekgalpi-android-v1.0.1-release.apk
```

**확인할 것 4가지** — `apksigner` 가 "Verifies" 를 찍었다고 끝이 아니다.

1. **서명 인증서가 그 키가 맞나** — 출력의 `Signer #1 certificate SHA-256 digest` 가
   §1 에서 기록해 둔 지문과 같아야 한다. **다른 키로 서명해도 `apksigner` 는 통과한다** —
   "서명이 유효한가"와 "우리 키로 서명했나"는 다른 질문이다.
2. **debug 빌드가 아닌가** — 아래가 **비어야** 한다. debug APK 로 시험하면 `application-debuggable`
   이 나오는 것으로 검사 자체가 동작하는지 확인할 수 있다.
   ```bash
   "$BT/aapt2" dump badging chaekgalpi-android-v1.0.1-release.apk | grep -i "debuggable\|testOnly"
   ```
3. **`testOnly` 가 아닌가** — 위 출력에 나오면 `adb install -t` 로만 설치되어 심사장에서
   파일 관리자로 설치할 수 없다.
4. **시작 URL 이 운영인가** — `strings <apk> | grep chaekgalpi.net`.
   단 이건 **스모크 테스트일 뿐이다** — 문자열이 있다는 것이 그 값이 `BuildConfig.START_URL`
   이라는 증명은 아니다. 진짜 근거는 빌드 가드(`verifyReleaseStartUrl`)와 **설치 후 첫 화면**이다.

### 4. 제출물 규칙

**제출하면 안 되는 것**

- `testOnly=true` APK — 파일 관리자로 설치되지 않는다
- `app-debug.apk` — cleartext 허용 + 로컬 서버(`10.0.2.2`)를 본다
- 서명되지 않은 release
- 로컬 URL 로 빌드한 APK
- **keystore 를 포함한 zip** — 키가 새면 앱 신원을 잃는다
- **서명 후 다시 압축한 APK** — 재압축은 서명을 깨뜨린다

**제출 패키지**

```text
책갈피_Android_제출/
├─ chaekgalpi-android-v1.0.1-release.apk
├─ APK_설치_및_체험안내.pdf
└─ SHA256.txt
```

`SHA256.txt` 는 `sha256sum` 출력 그대로 넣는다. 심사위원이 받은 파일이 우리가 만든 것과
같은지 확인할 수 있는 유일한 근거이며, **APK 를 다시 만들면 해시도 반드시 다시 계산한다.**

### versionCode 정책

- release 후보마다 **`versionCode` 를 +1** 한다. 되돌리지 않는다.
- 배포한 APK 보다 낮은 `versionCode` 로는 일반 업데이트 설치가 되지 않는다.
- `versionName` 은 사람이 읽는 값(`1.0.1`), `versionCode` 는 단조 증가하는 정수다.
  **`versionCode` 에는 소수점을 쓸 수 없다** — 매니페스트의 정수 필드이고 Gradle Kotlin DSL 에서도 `Int` 라
  `versionCode = 1.1` 은 컴파일되지 않는다. 소수점으로 올리고 싶은 것은 언제나 `versionName` 쪽이다.
- 이력: `1 / 1.0.0`(첫 대회 제출본) → **`2 / 1.0.1`**(원자료 내보내기 XLSX 전환 판).

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
├─ DEVICE_VERIFICATION.md   실기기 검증 체크리스트(Phase 10)
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
