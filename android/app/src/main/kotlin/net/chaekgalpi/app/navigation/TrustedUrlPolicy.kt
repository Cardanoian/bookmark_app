package net.chaekgalpi.app.navigation

import java.net.URI
import java.util.Locale

/**
 * 상위 화면 WebView 가 어떤 URL 을 직접 로드해도 되는지 판정한다.
 *
 * 네이티브 Bridge 가 붙은 WebView 에는 **신뢰한 서버 콘텐츠만** 로드해야 하므로,
 * 판정은 문자열 `contains`/`endsWith` 가 아니라 **URI 파싱 후 scheme·host 정확 비교**로 한다.
 * `https://chaekgalpi.net.evil.example` 같은 접미 위조를 문자열 비교로는 막을 수 없다.
 *
 * 순수 Kotlin 이라 Android 의존성 없이 JVM 단위 테스트로 전수 검증한다.
 */
object TrustedUrlPolicy {

    const val CANONICAL_HOST = "chaekgalpi.net"
    private const val WWW_HOST = "www.chaekgalpi.net"

    /** WebView 안에서 직접 열어도 되는 host 목록. 소문자로 비교한다. */
    private val INTERNAL_HOSTS = setOf(CANONICAL_HOST, WWW_HOST)

    /** 외부 앱(Custom Tab 이 아닌 시스템 Intent)으로 넘길 수 있는 scheme. */
    private val EXTERNAL_INTENT_SCHEMES = setOf("mailto", "tel", "sms")

    sealed interface Decision {
        /** Hotwire Navigator 내부 화면으로 연다. */
        data object Internal : Decision

        /** Android Custom Tab 으로 연다(신뢰하지 않는 https). */
        data object BrowserTab : Decision

        /** 처리 앱이 있으면 시스템 Intent 로 넘긴다(mailto/tel/sms). */
        data object SystemIntent : Decision

        /** 열지 않는다. javascript:/file:/content: 등 임의 탐색과 알 수 없는 scheme. */
        data object Reject : Decision
    }

    fun decide(url: String?): Decision {
        val uri = parse(url) ?: return Decision.Reject
        val scheme = uri.scheme?.lowercase(Locale.ROOT) ?: return Decision.Reject

        return when {
            scheme in EXTERNAL_INTENT_SCHEMES -> Decision.SystemIntent
            scheme != "https" -> Decision.Reject  // http 포함 — release 는 평문을 열지 않는다
            isInternalHost(uri) -> Decision.Internal
            else -> Decision.BrowserTab
        }
    }

    /** WebView 가 직접 로드해도 되는 신뢰 URL 인지. */
    fun isInternal(url: String?): Boolean = decide(url) is Decision.Internal

    private fun isInternalHost(uri: URI): Boolean {
        // userinfo 가 있으면 `https://chaekgalpi.net@evil.example/` 형태로 host 를 오인시킬 수 있다.
        if (uri.userInfo != null) return false
        // 기본 포트(-1 = 미지정, 443 = https 기본) 외에는 신뢰하지 않는다.
        if (uri.port != -1 && uri.port != 443) return false

        val host = uri.host?.lowercase(Locale.ROOT) ?: return false
        return host in INTERNAL_HOSTS
    }

    private fun parse(url: String?): URI? {
        if (url.isNullOrBlank()) return null
        return try {
            // URI 는 host 를 별도 필드로 파싱하므로 접미 위조에 안전하다.
            // host 가 null 이면(예: "https:///path", 상대 URL) 아래 검사에서 걸러진다.
            URI(url)
        } catch (e: Exception) {
            null
        }
    }
}
