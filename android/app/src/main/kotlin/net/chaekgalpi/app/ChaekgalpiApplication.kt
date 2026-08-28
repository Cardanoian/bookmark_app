package net.chaekgalpi.app

import android.app.Application
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.logging.HotwireLogLevel
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerFragmentDestinations
import net.chaekgalpi.app.navigation.ChaekgalpiWebFragment

/**
 * 앱 진입점. Activity 가 만들어지기 전에 Hotwire 설정을 끝낸다.
 */
class ChaekgalpiApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        configureHotwire()
        loadPathConfiguration()
    }

    private fun configureHotwire() {
        // ── User-Agent ──────────────────────────────────────────────────────────
        // **prefix 만 붙이고 WebView 기본 Chromium UA 를 절대 덮어쓰지 않는다.**
        // Hotwire 가 뒤에 "Hotwire Native Android; Turbo Native Android;" 를 덧붙이며,
        // 서버가 이 문자열에 두 가지를 동시에 의존한다:
        //   · `hotwire_native_app?`  → /(Turbo|Hotwire) Native/ 매칭
        //   · `allow_browser versions: :modern` → UA 에서 Chrome major 버전 파싱(120+ 필요)
        // prefix 에 버전을 넣어 두면 서버 로그에서 배포된 앱 버전 분포를 볼 수 있다(호환성 계약).
        Hotwire.config.applicationUserAgentPrefix = "Chaekgalpi Android/${BuildConfig.VERSION_NAME};"

        // ── 로그·디버깅 ─────────────────────────────────────────────────────────
        // release 에서는 학생 사진 URI·쿠키·응답 본문이 Logcat 에 남지 않아야 한다(아동 PII).
        Hotwire.config.logger.logLevel =
            if (BuildConfig.DEBUG) HotwireLogLevel.DEBUG else HotwireLogLevel.NONE
        Hotwire.config.webViewDebuggingEnabled = BuildConfig.DEBUG

        // ── 화면 등록 ───────────────────────────────────────────────────────────
        // 웹 브랜드 헤더와 중복되는 네이티브 툴바를 제거한 사용자 정의 Fragment 를 기본 목적지로 둔다.
        // 등록 API 는 `HotwireNavigation`(internal) 이 아니라 `Hotwire` 의 공개 확장 함수를 쓴다.
        Hotwire.defaultFragmentDestination = ChaekgalpiWebFragment::class
        Hotwire.registerFragmentDestinations(ChaekgalpiWebFragment::class)
    }

    /**
     * Path Configuration 은 번들 사본과 원격 사본을 함께 쓴다.
     *  · 번들(assets): 첫 실행과 원격 장애 때의 안전망. 이것만으로도 앱이 동작해야 한다.
     *  · 원격(서버)  : APK 재배포 없이 경로 동작을 조정하는 통로.
     * 단일 진실은 서버의 `config/hotwire_native/android_v1.json` 이고 assets 사본은 그 생성물이다.
     */
    private fun loadPathConfiguration() {
        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(
                assetFilePath = "json/path_configuration.json",
                remoteFileUrl = "${BuildConfig.START_URL}/configurations/android_v1.json"
            )
        )
    }
}
