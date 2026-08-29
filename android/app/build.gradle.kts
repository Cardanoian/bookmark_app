import java.io.FileInputStream
import java.net.URI
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// ---------------------------------------------------------------------------
// 시작 URL — Kotlin 소스에 하드코딩하지 않고 build type 별 BuildConfig 값 하나로 관리한다.
//
// release 는 운영 HTTPS 호스트만 허용한다. `-Pchaekgalpi.releaseStartUrl=…` 로 덮어쓸 수는 있지만
// 아래 `requireProductionUrl` 검증을 통과해야 하므로, 로컬·HTTP·타 호스트로는 release 를 만들 수 없다.
// (이 override 는 검증 로직 자체를 소스 수정 없이 시험하기 위한 것이다 — 계획 §J.5 C4)
// ---------------------------------------------------------------------------
val releaseStartUrl: String =
    providers.gradleProperty("chaekgalpi.releaseStartUrl").getOrElse("https://chaekgalpi.net")

// debug 는 에뮬레이터에서 호스트의 로컬 Rails 를 가리킨다(10.0.2.2 = 에뮬레이터가 보는 호스트 루프백).
// 실기기 debug 빌드는 `-Pchaekgalpi.debugStartUrl=http://<LAN IP>:3000` 으로 바꾼다.
val debugStartUrl: String =
    providers.gradleProperty("chaekgalpi.debugStartUrl").getOrElse("http://10.0.2.2:3000")

val canonicalHost = "chaekgalpi.net"

/** release 시작 URL 이 운영 HTTPS 호스트인지 문자열 비교가 아니라 URI 파싱으로 검증한다. */
fun requireProductionUrl(url: String) {
    val uri = try {
        URI(url)
    } catch (e: Exception) {
        throw GradleException("release START_URL 을 URI 로 파싱할 수 없습니다: '$url'")
    }
    if (uri.scheme != "https") {
        throw GradleException("release START_URL 은 https 여야 합니다. 현재: '$url'")
    }
    if (uri.host != canonicalHost) {
        throw GradleException("release START_URL 호스트는 '$canonicalHost' 여야 합니다. 현재: '${uri.host}'")
    }
    if (uri.userInfo != null) {
        throw GradleException("release START_URL 에 userinfo 를 넣을 수 없습니다: '$url'")
    }
    if (uri.port != -1) {
        throw GradleException("release START_URL 에 포트를 넣을 수 없습니다: '$url'")
    }
}

// keystore.properties 는 저장소 밖의 실제 키를 가리키는 로컬 전용 파일이다(.gitignore 대상).
// 값이 없으면 release 서명이 구성되지 않으며, 아래 verifyReleaseSigning 이 빌드를 명확히 실패시킨다.
// **debug 키로 자동 폴백하지 않는다.**
val keystorePropsFile = rootProject.file("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) FileInputStream(keystorePropsFile).use { load(it) }
}
val releaseKeystoreKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseKeystoreProps = keystorePropsFile.exists() &&
    releaseKeystoreKeys.all { !keystoreProps.getProperty(it).isNullOrBlank() }

// storeFile 이 **실제로 존재하는지**까지 본다. 값만 채워져 있고 파일이 없으면(예: 임시 경로에
// 만들었다가 지워진 키) 아래 verifyReleaseSigning 이 통과해 버리고, 빌드는 한참 뒤 Gradle 내부의
// `validateSigningRelease` 에서 원인을 알 수 없는 메시지로 죽는다 — 실제로 그 상태였다.
val releaseKeystoreFile = keystoreProps.getProperty("storeFile")?.let { rootProject.file(it) }
val hasReleaseKeystore = hasReleaseKeystoreProps && releaseKeystoreFile?.exists() == true

android {
    namespace = "net.chaekgalpi.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "net.chaekgalpi.app"
        minSdk = 28      // Hotwire Native Android 하한. 기준 기기 SM-P610 은 API 29 출시라 여유 통과.
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            buildConfigField("String", "START_URL", "\"$debugStartUrl\"")
        }
        release {
            isDebuggable = false
            // 첫 대회용 release 는 R8 이 Hotwire 클래스를 제거해 release 에서만 크래시하는 회귀를 피하려고
            // 축소·난독화를 끈다(계획 §1.2). 2차 릴리스에서 keep 규칙과 함께 재검토한다.
            isMinifyEnabled = false
            isShrinkResources = false
            buildConfigField("String", "START_URL", "\"$releaseStartUrl\"")
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }


    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}")
    }
}

// Kotlin JVM 타깃은 최상위 `kotlin` 확장에서 설정한다(`android {}` 안이 아니다).
// compileOptions 의 Java 17 과 반드시 같은 값이어야 컴파일러 간 불일치가 없다.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // Hotwire Native — core 가 appcompat·core-ktx·webkit 을 compile 로, material·constraintlayout·
    // okhttp·gson·coroutines 를 runtime 으로 가져온다. 코드에서 직접 쓰는 것은 아래에 명시 선언한다
    // (runtime scope 는 컴파일 클래스패스에 없다 — 계획 §D5).
    implementation("dev.hotwire:core:1.3.1")
    implementation("dev.hotwire:navigation-fragments:1.3.1")

    // core 가 이미 가져오는 것들의 scope 승격. 버전을 core 의 전이 버전과 일치시켜 충돌을 막는다.
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")

    // 사진 선택기(PickVisualMedia)·ActivityResult API.
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.fragment:fragment-ktx:1.8.5")

    testImplementation("junit:junit:4.13.2")
    // `org.json` 은 Android SDK 에 stub 으로만 들어 있어 JVM 단위 테스트에서 예외를 던진다.
    // 실제 구현을 테스트 클래스패스에만 올려 브리지 payload 파싱을 진짜로 검증한다(APK 미포함).
    testImplementation("org.json:json:20240303")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
}

// ---------------------------------------------------------------------------
// release 가드 — 두 검증을 통과하지 못하면 release 산출물을 만들지 않는다.
// ---------------------------------------------------------------------------

val verifyReleaseStartUrl by tasks.registering {
    group = "verification"
    description = "release 시작 URL 이 운영 HTTPS 호스트인지 검증한다."
    val url = releaseStartUrl
    doLast {
        requireProductionUrl(url)
        logger.lifecycle("release START_URL 검증 통과: $url")
    }
}

val verifyReleaseSigning by tasks.registering {
    group = "verification"
    description = "release 서명 키 설정이 존재하는지 검증한다. debug 키로 폴백하지 않는다."
    val propsPresent = hasReleaseKeystoreProps
    val storePath = releaseKeystoreFile?.absolutePath
    val storeExists = releaseKeystoreFile?.exists() == true
    val path = keystorePropsFile.absolutePath
    doLast {
        if (!propsPresent) {
            throw GradleException(
                """
                release 서명 키 설정이 없습니다.
                  기대 파일: $path
                  필요 키  : storeFile, storePassword, keyAlias, keyPassword
                debug 키로 자동 폴백하지 않습니다. android/README.md 의 서명 절차를 따르세요.
                """.trimIndent()
            )
        }
        if (!storeExists) {
            throw GradleException(
                """
                release 서명 키 파일이 없습니다.
                  keystore.properties: $path
                  storeFile          : $storePath
                설정은 채워져 있으나 그 경로에 키가 없습니다. 임시 경로에 만들었다가 지워진 키를
                가리키고 있지 않은지 확인하세요. debug 키로 자동 폴백하지 않습니다.
                """.trimIndent()
            )
        }
        logger.lifecycle("release 서명 설정 확인됨: $storePath")
    }
}

tasks.matching { it.name == "assembleRelease" || it.name == "bundleRelease" }.configureEach {
    dependsOn(verifyReleaseStartUrl, verifyReleaseSigning)
}
