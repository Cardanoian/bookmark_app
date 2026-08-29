package net.chaekgalpi.app.navigation

import java.net.URI
import java.util.Locale

/**
 * 방문 제안(VisitProposal)을 앱이 직접 처리할지, 라이브러리 기본 핸들러에 넘길지, 아예 막을지 판정한다.
 *
 * **왜 별도 순수 객체인가**
 * Hotwire 의 `Router.RouteDecisionHandler` 는 `VisitProposal`·`NavigatorConfiguration`·
 * `HotwireActivity` 를 받는데, 이들은 내부에서 `android.net.Uri` 를 쓰는 라이브러리 타입이라
 * JVM 단위 테스트에서 그대로 만들 수 없다. 판정 규칙만 여기로 분리해 두면
 * [TrustedUrlRouteDecisionHandler] 는 5줄짜리 어댑터가 되고, 규칙 전체를 순수 테스트로 고정할 수 있다.
 *
 * **기본 핸들러가 이미 하는 일**(navigation-fragments 1.3.1 실측: Router 의 기본 목록은
 * AppNavigation → BrowserTab → SystemNavigation 순이고, 아무 핸들러도 매칭되지 않으면 CANCEL 이다)
 *  · startLocation 과 host 가 같으면 앱 내 이동
 *  · 그 밖의 http/https 는 Custom Tab
 *  · mailto/tel 등은 시스템 Intent
 * 그래서 우리가 손대야 하는 것은 **기본 핸들러가 틀리게 처리하는 두 경우뿐**이다.
 */
object NativeRouting {

    enum class Route {
        /** 앱 내에서 연다. 기본 AppNavigation 과 동일한 NAVIGATE 결정이다. */
        InApp,

        /** 우리가 판단하지 않고 라이브러리 기본 핸들러 목록에 넘긴다. */
        Fallthrough,

        /** 열지 않는다. 사용자에게 이유를 알린다. */
        Blocked
    }

    /**
     * @param location 방문하려는 URL.
     * @param developmentOrigin debug 빌드의 로컬 서버 origin(예: `http://10.0.2.2:3000`).
     *   **release 에서는 반드시 null 이어야 한다** — 호출부가 `BuildConfig.DEBUG` 로 가드한다.
     *   debug 서버는 평문 http 라 [TrustedUrlPolicy] 가 당연히 거부하므로, 이 예외가 없으면
     *   debug 빌드에서 모든 이동이 막힌다.
     */
    fun route(location: String?, developmentOrigin: String?): Route {
        if (location.isNullOrBlank()) return Route.Blocked

        // debug 로컬 서버는 기본 핸들러(host 일치 → 앱 내 이동)에 그대로 맡긴다.
        // 접두 문자열 비교가 아니라 origin(scheme+host+port) 일치로 본다 —
        // "http://10.0.2.2:3000@evil.example/" 같은 접두 위조를 startsWith 로는 막을 수 없다.
        if (developmentOrigin != null && isSameOrigin(location, developmentOrigin)) {
            return Route.Fallthrough
        }

        return when (TrustedUrlPolicy.decide(location)) {
            // 신뢰 호스트는 우리가 직접 앱 내 이동으로 확정한다.
            // 기본 AppNavigation 은 startLocation 과 host 가 **완전히 같을 때만** 매칭하므로
            // `www.chaekgalpi.net` 이 Custom Tab 으로 새어 나간다. Custom Tab 은 앱 WebView 와
            // 쿠키 저장소가 달라서 로그인이 풀린 화면이 뜬다 — 학생이 겪으면 원인을 알 수 없는 사고다.
            TrustedUrlPolicy.Decision.Internal -> Route.InApp

            // javascript:/file:/content:/data: 와 알 수 없는 scheme.
            // 기본 라우터도 매칭 실패로 CANCEL 하지만 **조용히** 막아서 사용자는 버튼이 고장 난 줄 안다.
            // 여기서 가로채 이유를 안내한다(계획 §7.1 "거부하고 사용자 안내").
            TrustedUrlPolicy.Decision.Reject -> Route.Blocked

            // 외부 https → Custom Tab, mailto/tel → 시스템 Intent. 기본 핸들러가 이미 옳다.
            TrustedUrlPolicy.Decision.BrowserTab,
            TrustedUrlPolicy.Decision.SystemIntent -> Route.Fallthrough
        }
    }

    /**
     * 이 URL 에 **Rails 세션 쿠키를 실어 요청해도 되는지**. 인증 CSV 다운로드가 쓴다(계획 §7.3-2,5).
     *
     * [route] 와 따로 두는 이유: 외부 https 는 라우팅상 Fallthrough(Custom Tab)로 정상이지만,
     * 쿠키를 붙여서는 **절대 안 되는** 대상이다. 두 판정을 한 함수로 합치면 그 구분이 사라진다.
     * 리다이렉트는 매 홉마다 이 함수로 다시 검사한다 — 첫 URL 만 보면 신뢰 호스트가 외부로
     * 302 를 주는 순간 세션 쿠키가 그대로 따라간다.
     */
    fun allowsCredentialedRequest(location: String?, developmentOrigin: String?): Boolean {
        if (location.isNullOrBlank()) return false

        if (developmentOrigin != null && isSameOrigin(location, developmentOrigin)) return true

        return TrustedUrlPolicy.decide(location) is TrustedUrlPolicy.Decision.Internal
    }

    /** scheme·host·port 가 모두 같은 origin 인지. 하나라도 파싱되지 않으면 false. */
    private fun isSameOrigin(url: String, origin: String): Boolean {
        val a = parse(url) ?: return false
        val b = parse(origin) ?: return false

        if (a.userInfo != null) return false
        if (!a.scheme.equals(b.scheme, ignoreCase = true)) return false
        if (!a.host.equals(b.host, ignoreCase = true)) return false
        return effectivePort(a) == effectivePort(b)
    }

    /** 미지정 포트를 scheme 기본값으로 정규화한다. `https://h` 와 `https://h:443` 은 같은 origin 이다. */
    private fun effectivePort(uri: URI): Int {
        if (uri.port != -1) return uri.port
        return when (uri.scheme?.lowercase(Locale.ROOT)) {
            "https" -> 443
            "http" -> 80
            else -> -1
        }
    }

    private fun parse(url: String): URI? = try {
        URI(url).takeIf { it.host != null }
    } catch (e: Exception) {
        null
    }
}
