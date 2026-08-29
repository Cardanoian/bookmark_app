package net.chaekgalpi.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import dev.hotwire.core.turbo.webview.WebViewVersionCompatibility
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import net.chaekgalpi.app.downloads.DownloadCoordinator

/**
 * 단일 [NavigatorConfiguration] 을 가진 Hotwire 셸 Activity.
 * 화면 스택·뒤로가기·화면 전환은 전부 Hotwire 가 관리한다.
 */
class MainActivity : HotwireActivity() {

    /**
     * 인증 파일 저장의 단일 창구. Fragment 가 아니라 Activity 에 두는 이유는
     * [DownloadCoordinator] 주석 참고(저장 위치 선택 중 화면 전환, 두 진입 경로).
     *
     * **onCreate 안에서 생성해야 한다** — 내부에서 ActivityResult 를 등록하므로 STARTED 이후에는
     * 예외가 난다. lazy 로 미루면 첫 다운로드 시점에 터진다.
     */
    lateinit var downloads: DownloadCoordinator
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        downloads = DownloadCoordinator(
            activity = this,
            // release 에서는 null 이라 운영 호스트에만 세션 쿠키를 싣는다.
            developmentOrigin = if (BuildConfig.DEBUG) BuildConfig.START_URL else null
        )
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        applySystemBarInsets()
        warnIfWebViewOutdated()
    }

    override fun onDestroy() {
        downloads.shutdown()
        super.onDestroy()
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "main",
            startLocation = BuildConfig.START_URL,
            navigatorHostId = R.id.main_nav_host
        )
    )

    /**
     * 상태바·내비게이션바·IME 만큼 패딩을 준다.
     * Galaxy Tab 의 3버튼 내비게이션과 제스처 내비게이션 양쪽에서 하단 콘텐츠(제출 버튼 등)가
     * 시스템 UI 에 가리지 않아야 한다.
     */
    private fun applySystemBarInsets() {
        val host = findViewById<android.view.View>(R.id.main_nav_host)
        ViewCompat.setOnApplyWindowInsetsListener(host) { view, windowInsets ->
            val bars = windowInsets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            val ime = windowInsets.getInsets(WindowInsetsCompat.Type.ime())
            view.updatePadding(
                left = bars.left,
                top = bars.top,
                right = bars.right,
                // 키보드가 올라오면 그만큼 밀어 올려 입력칸과 제출 버튼이 가리지 않게 한다.
                bottom = maxOf(bars.bottom, ime.bottom)
            )
            WindowInsetsCompat.CONSUMED
        }
    }

    /**
     * 기기의 Android System WebView(또는 Chrome)가 서버 정책보다 낮으면 **406 이 나기 전에**
     * 네이티브 다이얼로그로 안내하고 Play 스토어로 보낸다.
     *
     * 서버는 `allow_browser versions: :modern` 으로 Chrome 120 미만을 406 으로 막는다.
     * 그 상태로 앱을 열면 로그인 화면조차 뜨지 않고 원인도 알 수 없으므로, 시작 시 먼저 확인한다.
     * 다이얼로그 문구는 `res/values/strings.xml` 에서 core 리소스를 override 해 한국어로 제공한다.
     */
    private fun warnIfWebViewOutdated() {
        WebViewVersionCompatibility.displayUpdateDialogIfOutdated(this, REQUIRED_WEBVIEW_VERSION)
    }

    companion object {
        /**
         * 서버 `allow_browser versions: :modern` 의 Chrome 최소 major 버전과 **같은 값**이다
         * (actionpack 8.1.3.1 실측: `{safari: 17.2, chrome: 120, firefox: 121, opera: 106}`).
         * 서버 정책을 바꾸면 이 상수도 함께 바꾼다 — 한쪽만 바꾸면 406 을 사전 차단하지 못한다.
         */
        const val REQUIRED_WEBVIEW_VERSION = 120
    }
}
