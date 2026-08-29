package net.chaekgalpi.app

import android.app.Application
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.logging.HotwireLogLevel
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerFragmentDestinations
import dev.hotwire.navigation.config.registerRouteDecisionHandlers
import dev.hotwire.navigation.routing.AppNavigationRouteDecisionHandler
import dev.hotwire.navigation.routing.BrowserTabRouteDecisionHandler
import dev.hotwire.navigation.routing.SystemNavigationRouteDecisionHandler
import net.chaekgalpi.app.navigation.ChaekgalpiWebFragment
import net.chaekgalpi.app.navigation.DownloadRouteDecisionHandler
import net.chaekgalpi.app.navigation.TrustedUrlRouteDecisionHandler

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

        configureRouting()
    }

    /**
     * URL 신뢰 판정을 기본 라우터 **앞**에 끼운다.
     *
     * 등록하면 라이브러리 기본 3종(AppNavigation → BrowserTab → SystemNavigation)이 뒤로 밀리고,
     * 우리 핸들러가 매칭하지 않은 것만 기존대로 처리된다. 고치는 것은 두 가지다.
     *  · `www.chaekgalpi.net` — 기본 AppNavigation 은 startLocation 과 host 가 완전히 같을 때만
     *    매칭해서 www 가 Custom Tab 으로 새어 나간다(쿠키가 달라 로그아웃 화면이 뜬다).
     *  · javascript:/file:/content: — 기본 라우터도 막지만 조용히 막아서 사용자는 버튼 고장으로 오해한다.
     *
     * developmentOrigin 은 **debug 빌드에서만** 넘긴다. debug 서버는 평문 http 라 신뢰 정책이 당연히
     * 거부하므로, 이 예외가 없으면 debug 빌드에서 모든 이동이 막힌다. release 에서는 null 이 되어
     * 운영 호스트 외에는 앱 WebView 안으로 들어올 수 없다.
     */
    private fun configureRouting() {
        Hotwire.registerRouteDecisionHandlers(
            // 다운로드 표시가 가장 먼저다. 그 뒤 어떤 핸들러가 매칭돼도 화면 이동이 일어나면
            // Turbo 가 CSV 를 방문으로 처리해 실패 화면 + 헛 감사 로그가 남는다.
            DownloadRouteDecisionHandler(),
            TrustedUrlRouteDecisionHandler(
                developmentOrigin = if (BuildConfig.DEBUG) BuildConfig.START_URL else null
            ),
            AppNavigationRouteDecisionHandler(),
            BrowserTabRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler()
        )
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
