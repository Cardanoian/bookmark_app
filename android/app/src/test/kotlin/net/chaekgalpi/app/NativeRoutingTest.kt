package net.chaekgalpi.app

import net.chaekgalpi.app.navigation.NativeRouting
import net.chaekgalpi.app.navigation.NativeRouting.Route
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 기본 라우터 앞에 끼우는 판정의 전수 검증.
 *
 * 이 규칙이 틀리면 증상이 둘 다 조용하다 — 링크가 아무 반응 없이 죽거나, 로그인이 풀린 Custom Tab 이
 * 뜬다. 어느 쪽도 앱에서는 원인을 알 수 없으므로 규칙 자체를 테스트로 고정한다.
 */
class NativeRoutingTest {

    private val devOrigin = "http://10.0.2.2:3000"

    // ---- release 빌드(개발 origin 없음) ----

    @Test fun `운영 호스트는 앱 안에서 연다`() {
        assertEquals(Route.InApp, NativeRouting.route("https://chaekgalpi.net/", null))
        assertEquals(Route.InApp, NativeRouting.route("https://chaekgalpi.net/reports/1", null))
    }

    @Test fun `www 도 앱 안에서 연다`() {
        // 이 한 줄이 이 클래스의 존재 이유다. 기본 AppNavigation 은 startLocation 과 host 가 완전히
        // 같을 때만 매칭해서 www 를 Custom Tab 으로 흘린다 — 쿠키가 달라 로그아웃 화면이 뜬다.
        assertEquals(Route.InApp, NativeRouting.route("https://www.chaekgalpi.net/reports/1", null))
    }

    @Test fun `외부 https 는 기본 핸들러에 넘긴다`() {
        // BrowserTabRouteDecisionHandler 가 Custom Tab 으로 연다. 우리가 가로채지 않는다.
        assertEquals(Route.Fallthrough, NativeRouting.route("https://library.example.kr/", null))
        assertEquals(Route.Fallthrough, NativeRouting.route("https://www.google.com/search?q=x", null))
    }

    @Test fun `mailto 와 tel 은 기본 핸들러에 넘긴다`() {
        assertEquals(Route.Fallthrough, NativeRouting.route("mailto:teacher@example.com", null))
        assertEquals(Route.Fallthrough, NativeRouting.route("tel:0212345678", null))
    }

    @Test fun `위험 scheme 은 막고 안내한다`() {
        assertEquals(Route.Blocked, NativeRouting.route("javascript:alert(1)", null))
        assertEquals(Route.Blocked, NativeRouting.route("file:///data/data/net.chaekgalpi.app/", null))
        assertEquals(Route.Blocked, NativeRouting.route("content://media/external/images/1", null))
        assertEquals(Route.Blocked, NativeRouting.route("data:text/html,<script>x</script>", null))
    }

    @Test fun `평문 http 는 운영 호스트라도 막는다`() {
        // release 는 usesCleartextTraffic=false 라 어차피 로드되지 않는다. 라우팅에서도 같은 답을 준다.
        assertEquals(Route.Blocked, NativeRouting.route("http://chaekgalpi.net/", null))
    }

    @Test fun `빈 URL 은 막는다`() {
        assertEquals(Route.Blocked, NativeRouting.route(null, null))
        assertEquals(Route.Blocked, NativeRouting.route("", null))
        assertEquals(Route.Blocked, NativeRouting.route("   ", null))
    }

    @Test fun `접미 위조 호스트는 앱 안으로 들이지 않는다`() {
        // Custom Tab(Fallthrough)으로는 열리되, Bridge 가 붙은 앱 WebView 안에는 절대 들어오지 않는다.
        assertEquals(Route.Fallthrough, NativeRouting.route("https://chaekgalpi.net.evil.example/", null))
        assertEquals(Route.Fallthrough, NativeRouting.route("https://chaekgalpi.net@evil.example/", null))
    }

    // ---- debug 빌드(개발 origin 있음) ----

    @Test fun `debug 로컬 서버는 기본 핸들러에 넘긴다`() {
        // 이 예외가 없으면 평문 http 라 Blocked 가 되어 debug 빌드에서 모든 이동이 막힌다.
        assertEquals(Route.Fallthrough, NativeRouting.route("http://10.0.2.2:3000/", devOrigin))
        assertEquals(Route.Fallthrough, NativeRouting.route("http://10.0.2.2:3000/session/new", devOrigin))
    }

    @Test fun `debug 예외는 origin 이 정확히 같을 때만 적용된다`() {
        // 포트가 다르면 다른 origin 이다.
        assertEquals(Route.Blocked, NativeRouting.route("http://10.0.2.2:4000/", devOrigin))
        // host 가 다르면 다른 origin 이다.
        assertEquals(Route.Blocked, NativeRouting.route("http://10.0.2.3:3000/", devOrigin))
        // scheme 이 다르면 다른 origin 이다(https 는 신뢰 정책으로 넘어가 외부 취급).
        assertEquals(Route.Fallthrough, NativeRouting.route("https://10.0.2.2:3000/", devOrigin))
    }

    @Test fun `debug 예외를 접두 위조로 통과시킬 수 없다`() {
        // startsWith 비교였다면 뚫린다. origin 파싱이라 host 는 evil.example 로 잡힌다.
        assertEquals(Route.Blocked, NativeRouting.route("http://10.0.2.2:3000@evil.example/", devOrigin))
        assertEquals(Route.Blocked, NativeRouting.route("http://10.0.2.2:3000.evil.example/", devOrigin))
    }

    @Test fun `debug 에서도 운영 호스트는 앱 안에서 연다`() {
        assertEquals(Route.InApp, NativeRouting.route("https://chaekgalpi.net/", devOrigin))
    }

    @Test fun `debug 에서도 위험 scheme 은 막는다`() {
        assertEquals(Route.Blocked, NativeRouting.route("javascript:alert(1)", devOrigin))
    }

    // ---- 세션 쿠키를 실어도 되는 대상 (인증 CSV 다운로드) ----

    @Test fun `운영 호스트에는 쿠키를 실어 요청한다`() {
        assertTrue(NativeRouting.allowsCredentialedRequest("https://chaekgalpi.net/teacher/exports.csv", null))
        assertTrue(NativeRouting.allowsCredentialedRequest("https://www.chaekgalpi.net/agree.pdf", null))
    }

    @Test fun `외부 호스트에는 쿠키를 절대 싣지 않는다`() {
        // 라우팅상으로는 Custom Tab 으로 여는 정상 대상이지만, 쿠키를 붙이면 세션 유출이다.
        assertEquals(Route.Fallthrough, NativeRouting.route("https://evil.example/steal", null))
        assertFalse(NativeRouting.allowsCredentialedRequest("https://evil.example/steal", null))
    }

    @Test fun `접미 위조 호스트에는 쿠키를 싣지 않는다`() {
        assertFalse(NativeRouting.allowsCredentialedRequest("https://chaekgalpi.net.evil.example/x.csv", null))
        assertFalse(NativeRouting.allowsCredentialedRequest("https://chaekgalpi.net@evil.example/x.csv", null))
    }

    @Test fun `평문 http 에는 쿠키를 싣지 않는다`() {
        assertFalse(NativeRouting.allowsCredentialedRequest("http://chaekgalpi.net/x.csv", null))
    }

    @Test fun `debug 로컬 서버에는 쿠키를 싣는다`() {
        assertTrue(NativeRouting.allowsCredentialedRequest("http://10.0.2.2:3000/teacher/exports.csv", devOrigin))
        // release 는 developmentOrigin 이 null 이라 같은 URL 이 거부된다.
        assertFalse(NativeRouting.allowsCredentialedRequest("http://10.0.2.2:3000/teacher/exports.csv", null))
    }

    @Test fun `빈 URL 에는 쿠키를 싣지 않는다`() {
        assertFalse(NativeRouting.allowsCredentialedRequest(null, devOrigin))
        assertFalse(NativeRouting.allowsCredentialedRequest("", devOrigin))
    }
}
