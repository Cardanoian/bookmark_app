package net.chaekgalpi.app.navigation

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.widget.Toolbar
import dev.hotwire.core.turbo.webview.HotwireWebView
import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebFragment
import net.chaekgalpi.app.MainActivity
import net.chaekgalpi.app.R

/**
 * 기본 웹 화면. 공식 [HotwireWebFragment] 를 그대로 쓰되 **네이티브 AppBar 만** 제거하고,
 * 라이브러리가 처리하지 않는 **파일 다운로드**를 맡는다.
 *
 * Rails 가 렌더하는 노란 브랜드 헤더가 이미 제목·내비게이션을 담당하므로 네이티브 툴바가 함께 뜨면
 * 화면 위쪽에 헤더가 두 겹으로 보인다.
 *
 * 주의: 레이아웃에서 AppBar 만 걷어내고 `@layout/hotwire_view` include 는 **유지**한다.
 * 그 안에 WebView 컨테이너뿐 아니라 로딩 progress 와 오류 화면이 들어 있어서,
 * 통째로 교체하면 툴바와 함께 오류·재시도 UI 까지 사라진다.
 *
 * Hotwire 내부 클래스를 복사하지 않고 공식 확장 지점(Fragment subclassing)만 쓴다.
 */
@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
class ChaekgalpiWebFragment : HotwireWebFragment() {

    /**
     * 지금 이 화면에 붙어 있는 WebView. Android 인쇄가 `createPrintDocumentAdapter` 를 쓰려면
     * 참조가 필요한데 `HotwireView` 는 WebView 를 공개하지 않는다. 공식 콜백으로 받은 값을
     * 붙어 있는 동안만 들고 있는다(detach 에서 비워 누수를 막는다).
     */
    var attachedWebView: HotwireWebView? = null
        private set

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_chaekgalpi_web, container, false)
    }

    /**
     * 네이티브 툴바가 없으므로 null 을 돌려준다. Hotwire 는 이 값이 없으면 툴바 연동(제목 표시·
     * 뒤로가기 버튼)을 건너뛰고, **Android 시스템 뒤로가기와 내비게이션 스택은 그대로 동작한다.**
     */
    override fun toolbarForNavigation(): Toolbar? = null

    // ── 다운로드 ───────────────────────────────────────────────────────────────

    /**
     * core 가 Session 생성 시 설치하는 기본 DownloadListener 를 **우리 것으로 바꾼다.**
     *
     * 기본 리스너는 다운로드 URL 을 그대로 `visitProposedToLocation` 으로 되던진다(실측). 그러면
     * 라우터가 같은 URL 로 앱 내 이동 → WebView 가 다시 다운로드로 판정 → 또 제안, 이 반복이라
     * 파일이 저장되지 않는다.
     *
     * 이 리스너는 **안전망**이다. 주 경로는 Path Configuration 의 `download: true` 표시를 읽는
     * [DownloadRouteDecisionHandler] 이고(그쪽은 Turbo 가 링크를 가로채기 전에 잡는다),
     * 여기는 표시되지 않은 경로인데 WebView 가 첨부로 판정한 응답을 받는다. 이때는
     * `Content-Disposition` 원문이 있어 파일명을 더 정확히 뽑을 수 있다.
     *
     * WebView 는 Session 이 공유하지만 한 시점에 붙어 있는 Fragment 는 하나뿐이고,
     * 다운로드 이벤트는 항상 붙어 있는 동안 도착한다. detach 에서 해제해 Fragment 누수를 막는다.
     */
    override fun onWebViewAttached(webView: HotwireWebView) {
        super.onWebViewAttached(webView)
        attachedWebView = webView

        webView.setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
            (activity as? MainActivity)?.downloads?.request(
                url = url,
                userAgent = userAgent,
                contentDisposition = contentDisposition,
                mimeType = mimeType
            )
        }
    }

    override fun onWebViewDetached(webView: HotwireWebView) {
        attachedWebView = null
        webView.setDownloadListener(null)
        super.onWebViewDetached(webView)
    }
}
