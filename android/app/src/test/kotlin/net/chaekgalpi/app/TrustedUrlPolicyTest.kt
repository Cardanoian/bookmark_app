package net.chaekgalpi.app

import net.chaekgalpi.app.navigation.TrustedUrlPolicy
import net.chaekgalpi.app.navigation.TrustedUrlPolicy.Decision
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * WebView 가 직접 로드해도 되는 URL 판정의 전수 검증.
 * 계획 §10.2 의 `TrustedUrlPolicyTest` 항목(정확 host 허용 / 접미 위조 거부 / HTTP 거부 /
 * userinfo·port·대소문자 경계)에 대응한다.
 */
class TrustedUrlPolicyTest {

    // ---- 내부(신뢰) ----

    @Test fun `운영 호스트는 내부로 연다`() {
        assertEquals(Decision.Internal, TrustedUrlPolicy.decide("https://chaekgalpi.net/"))
        assertEquals(Decision.Internal, TrustedUrlPolicy.decide("https://chaekgalpi.net/session/new"))
        assertEquals(Decision.Internal, TrustedUrlPolicy.decide("https://www.chaekgalpi.net/reports/1"))
    }

    @Test fun `호스트 대소문자는 무시한다`() {
        assertEquals(Decision.Internal, TrustedUrlPolicy.decide("https://CHAEKGALPI.NET/"))
        assertEquals(Decision.Internal, TrustedUrlPolicy.decide("https://Www.Chaekgalpi.Net/"))
    }

    @Test fun `명시적 443 포트는 허용한다`() {
        assertEquals(Decision.Internal, TrustedUrlPolicy.decide("https://chaekgalpi.net:443/up"))
    }

    @Test fun `쿼리와 프래그먼트가 있어도 내부다`() {
        assertEquals(
            Decision.Internal,
            TrustedUrlPolicy.decide("https://chaekgalpi.net/books/search?q=%EA%B0%95%EC%95%84%EC%A7%80#top")
        )
    }

    // ---- 접미·접두 위조 (문자열 비교였다면 뚫리는 것들) ----

    @Test fun `접미 위조 호스트를 거부한다`() {
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://chaekgalpi.net.evil.example/"))
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://evil-chaekgalpi.net/"))
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://notchaekgalpi.net/"))
    }

    @Test fun `서브도메인은 내부가 아니다`() {
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://api.chaekgalpi.net/"))
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://evil.chaekgalpi.net/"))
    }

    @Test fun `userinfo 로 호스트를 오인시킬 수 없다`() {
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://chaekgalpi.net@evil.example/"))
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://user:pw@chaekgalpi.net/"))
    }

    @Test fun `비표준 포트는 내부가 아니다`() {
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://chaekgalpi.net:8443/"))
    }

    // ---- 평문·위험 scheme ----

    @Test fun `http 는 운영 호스트라도 거부한다`() {
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide("http://chaekgalpi.net/"))
    }

    @Test fun `위험 scheme 을 거부한다`() {
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide("javascript:alert(1)"))
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide("file:///etc/passwd"))
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide("content://media/external/images/1"))
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide("intent://scan/#Intent;scheme=zxing;end"))
    }

    @Test fun `빈 값과 상대 경로를 거부한다`() {
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide(null))
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide(""))
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide("   "))
        assertEquals(Decision.Reject, TrustedUrlPolicy.decide("/reports/1"))
    }

    // ---- 외부 Intent ----

    @Test fun `mailto tel sms 는 시스템 Intent 로 넘긴다`() {
        assertEquals(Decision.SystemIntent, TrustedUrlPolicy.decide("mailto:teacher@example.com"))
        assertEquals(Decision.SystemIntent, TrustedUrlPolicy.decide("tel:01012345678"))
        assertEquals(Decision.SystemIntent, TrustedUrlPolicy.decide("sms:01012345678"))
    }

    // ---- 외부 https (인근 도서관 홈페이지 등) ----

    @Test fun `그 밖의 https 는 Custom Tab 으로 연다`() {
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://www.nl.go.kr/"))
        assertEquals(Decision.BrowserTab, TrustedUrlPolicy.decide("https://library.example.kr/book/1"))
    }

    // ---- 편의 API ----

    @Test fun `isInternal 은 decide 와 일치한다`() {
        assert(TrustedUrlPolicy.isInternal("https://chaekgalpi.net/"))
        assert(!TrustedUrlPolicy.isInternal("https://chaekgalpi.net.evil.example/"))
        assert(!TrustedUrlPolicy.isInternal("http://chaekgalpi.net/"))
    }
}
