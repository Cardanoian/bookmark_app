package net.chaekgalpi.app.navigation

import dev.hotwire.core.turbo.visit.VisitProposal
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router
import net.chaekgalpi.app.MainActivity

/**
 * Path Configuration 이 `download: true` 로 표시한 경로를 **화면 이동 대신 파일 저장으로** 처리한다.
 *
 * **왜 필요한가 (실측)**: 표시가 없으면 교사 CSV 링크는 Turbo 가 가로채 방문으로 처리한다.
 * CSV 응답은 HTML 이 아니므로 `visitRequestFailedWithNonHttpStatusCode` 로 끝나고, 화면에는
 * "화면을 불러오지 못했어요"만 남는다. 그런데 방문 요청 자체는 서버까지 갔기 때문에
 * **`teacher.reports_csv_download` 감사 로그가 기록된다** — 아무도 받지 못한 파일이 내려받아진 것으로
 * 남는 상태였다. WebView 의 DownloadListener 는 이 경로에서 아예 호출되지 않는다.
 *
 * **왜 URL 패턴을 Kotlin 에 넣지 않는가**: 대상 경로가 늘어날 때 APK 를 다시 배포해야 한다.
 * 원격 Path Configuration 에 규칙을 두면 서버에서 즉시 조정할 수 있고, 규칙의 단일 진실이
 * `config/hotwire_native/android_v1.json` 한 곳에 남는다.
 *
 * 신뢰 호스트 검사는 여기서 하지 않는다 — [net.chaekgalpi.app.downloads.DownloadCoordinator] 가
 * 세션 쿠키를 싣기 직전에 [NativeRouting.allowsCredentialedRequest] 로 확인하고, 리다이렉트
 * 매 홉마다 다시 확인한다. 검사를 실제 사용 지점에 두어 우회 경로가 생기지 않게 한다.
 */
class DownloadRouteDecisionHandler : Router.RouteDecisionHandler {

    override val name = "chaekgalpi-download"

    override fun matches(
        proposal: VisitProposal,
        configuration: NavigatorConfiguration
    ): Boolean = isDownload(proposal)

    override fun handle(
        proposal: VisitProposal,
        configuration: NavigatorConfiguration,
        activity: HotwireActivity
    ): Router.Decision {
        (activity as? MainActivity)?.downloads?.request(
            url = proposal.location,
            // 라우팅 시점에는 응답 헤더가 없다. 서버가 원격 설정으로 내려 준 값이 있으면 그것을 쓴다.
            mimeType = stringProperty(proposal, "download_mime"),
            suggestedName = stringProperty(proposal, "download_filename")
        )

        // 화면은 이동하지 않는다. 사용자는 보던 목록에 그대로 남고 저장 위치 선택창만 뜬다.
        return Router.Decision.CANCEL
    }

    /**
     * JSON 의 `true` 를 Gson 이 무엇으로 주든 받아들인다. properties 는 `HashMap<String, Any>` 라
     * 라이브러리 버전이나 파서 설정에 따라 Boolean·String 어느 쪽으로도 올 수 있다.
     */
    private fun stringProperty(proposal: VisitProposal, key: String): String? =
        (proposal.properties[key] as? String)?.takeIf { it.isNotBlank() }

    private fun isDownload(proposal: VisitProposal): Boolean =
        when (val value = proposal.properties["download"]) {
            is Boolean -> value
            is String -> value.equals("true", ignoreCase = true)
            else -> false
        }
}
